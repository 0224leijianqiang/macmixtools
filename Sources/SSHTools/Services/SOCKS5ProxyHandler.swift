import Foundation
import NIO

/// Establishes a SOCKS5 CONNECT tunnel (no-auth) to `targetHost:targetPort`.
///
/// Designed to be used as a *pre-handler* in a pipeline (e.g. Citadel's `channelHandlers`),
/// so it intentionally delays `channelActive` propagation until the tunnel is established.
final class SOCKS5ProxyHandler: ChannelDuplexHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    enum State {
        case initial
        case sentGreeting
        case sentRequest
        case connected
        case failed
    }

    private var state: State = .initial
    private let targetHost: String
    private let targetPort: Int

    private var didForwardChannelActive = false
    private var inboundBuffer: ByteBuffer?

    private var pendingWrites: [(NIOAny, EventLoopPromise<Void>?)] = []
    private var pendingFlush = false

    init(targetHost: String, targetPort: Int) {
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            startHandshake(context: context)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        startHandshake(context: context)
        // Intentionally NOT forwarding channelActive until SOCKS is connected.
    }

    private func startHandshake(context: ChannelHandlerContext) {
        guard state == .initial else { return }
        sendGreeting(context: context)
    }

    private func sendGreeting(context: ChannelHandlerContext) {
        Logger.log("SOCKS5: Sending greeting", level: .debug)
        var buffer = context.channel.allocator.buffer(capacity: 3)
        buffer.writeBytes([0x05, 0x01, 0x00]) // ver=5, nmethods=1, method=no-auth
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        state = .sentGreeting
    }

    private func sendConnectRequest(context: ChannelHandlerContext) {
        Logger.log("SOCKS5: Sending connect request to \(targetHost):\(targetPort)", level: .debug)

        let hostBytes = Array(targetHost.utf8)
        let hostLen = hostBytes.count
        guard hostLen <= 255 else {
            fail(context: context, message: "Target host too long for SOCKS5 domain encoding (\(hostLen) bytes)")
            return
        }

        let capacity = 4 + 1 + hostLen + 2
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        buffer.writeBytes([0x05, 0x01, 0x00, 0x03]) // ver=5, cmd=connect, rsv=0, atyp=domain
        buffer.writeInteger(UInt8(hostLen))
        buffer.writeBytes(hostBytes)
        buffer.writeInteger(UInt16(targetPort), endianness: .big)

        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        state = .sentRequest
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        if inboundBuffer == nil {
            inboundBuffer = context.channel.allocator.buffer(capacity: max(64, incoming.readableBytes))
        }
        inboundBuffer?.writeBuffer(&incoming)
        processInbound(context: context)
    }

    private func processInbound(context: ChannelHandlerContext) {
        guard var buffer = inboundBuffer else { return }

        while true {
            switch state {
            case .sentGreeting:
                guard buffer.readableBytes >= 2 else {
                    inboundBuffer = buffer
                    return
                }
                let version = buffer.readInteger(as: UInt8.self)
                let method = buffer.readInteger(as: UInt8.self)
                Logger.log("SOCKS5: Received greeting response ver=\(version ?? 0) method=\(method ?? 255)", level: .debug)

                guard version == 0x05, method == 0x00 else {
                    inboundBuffer = buffer
                    fail(context: context, message: "Unsupported auth method: \(String(describing: method))")
                    return
                }

                sendConnectRequest(context: context)
                continue

            case .sentRequest:
                // Reply: VER REP RSV ATYP BND.ADDR BND.PORT
                guard buffer.readableBytes >= 4 else {
                    inboundBuffer = buffer
                    return
                }

                let version = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self)
                let reply = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self)
                let atyp = buffer.getInteger(at: buffer.readerIndex + 3, as: UInt8.self)

                var requiredLen = 4
                switch atyp {
                case 0x01: requiredLen += 4 + 2
                case 0x04: requiredLen += 16 + 2
                case 0x03:
                    guard buffer.readableBytes >= 5 else {
                        inboundBuffer = buffer
                        return
                    }
                    let domainLen = Int(buffer.getInteger(at: buffer.readerIndex + 4, as: UInt8.self) ?? 0)
                    requiredLen += 1 + domainLen + 2
                default:
                    // Unknown ATYP; wait for more to avoid desync then fail.
                    inboundBuffer = buffer
                    fail(context: context, message: "Unsupported ATYP: \(String(describing: atyp))")
                    return
                }

                guard buffer.readableBytes >= requiredLen else {
                    inboundBuffer = buffer
                    return
                }

                guard version == 0x05, reply == 0x00 else {
                    inboundBuffer = buffer
                    fail(context: context, message: "CONNECT failed (REP=\(String(describing: reply)))")
                    return
                }

                Logger.log("SOCKS5: Connection established to target", level: .info)
                state = .connected
                buffer.moveReaderIndex(forwardBy: requiredLen)

                // Now let downstream handlers (SSH) see channelActive and start their handshake.
                if !didForwardChannelActive {
                    didForwardChannelActive = true
                    context.fireChannelActive()
                }

                // Flush any buffered outbound writes (defensive; usually empty because channelActive was delayed).
                flushPendingWrites(context: context)

                // Forward any remaining inbound bytes (rare, but possible with coalescing).
                if buffer.readableBytes > 0 {
                    inboundBuffer = nil
                    context.fireChannelRead(wrapInboundOut(buffer))
                } else {
                    inboundBuffer = nil
                }

                // Once connected, remove ourselves to keep the pipeline simple.
                context.pipeline.removeHandler(self, promise: nil)
                return

            case .connected:
                inboundBuffer = nil
                context.fireChannelRead(wrapInboundOut(buffer))
                return

            default:
                inboundBuffer = buffer
                return
            }
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if state == .connected {
            context.write(data, promise: promise)
        } else {
            pendingWrites.append((data, promise))
        }
    }

    func flush(context: ChannelHandlerContext) {
        if state == .connected {
            context.flush()
        } else {
            pendingFlush = true
        }
    }

    private func flushPendingWrites(context: ChannelHandlerContext) {
        guard !pendingWrites.isEmpty else {
            if pendingFlush {
                pendingFlush = false
                context.flush()
            }
            return
        }

        let writes = pendingWrites
        pendingWrites.removeAll(keepingCapacity: true)

        for (data, promise) in writes {
            context.write(data, promise: promise)
        }
        context.flush()
        pendingFlush = false
    }

    private func fail(context: ChannelHandlerContext, message: String) {
        guard state != .failed else { return }
        state = .failed
        Logger.log("SOCKS5: Error - \(message)", level: .error)

        for (_, promise) in pendingWrites {
            promise?.fail(ChannelError.ioOnClosedChannel)
        }
        pendingWrites.removeAll()
        pendingFlush = false
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(context: context, message: error.localizedDescription)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if state != .connected && state != .failed {
            fail(context: context, message: "Proxy channel closed before SOCKS5 handshake completed")
        }
        context.fireChannelInactive()
    }
}


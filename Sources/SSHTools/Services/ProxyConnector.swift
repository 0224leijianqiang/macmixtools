import Foundation
import NIO

class ProxyConnector {
    static func connect(
        proxyHost: String,
        proxyPort: Int,
        targetHost: String,
        targetPort: Int,
        group: MultiThreadedEventLoopGroup = .singleton
    ) async throws -> Channel {
        Logger.log("ProxyConnector: Connecting to proxy at \(proxyHost):\(proxyPort)", level: .debug)
        
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.connectTimeout, value: .seconds(10))
        
        let channel = try await bootstrap.connect(host: proxyHost, port: proxyPort).get()
        Logger.log("ProxyConnector: Connected to proxy TCP", level: .debug)
        
        let promise = channel.eventLoop.makePromise(of: Void.self)
        
        // Add our manual SOCKS5 handshake handler
        let handler = ManualSOCKS5Handler(
            targetHost: targetHost,
            targetPort: targetPort,
            completionPromise: promise
        )
        
        try await channel.pipeline.addHandler(handler).get()
        
        // Wait for handshake to complete
        try await promise.futureResult.get()
        Logger.log("ProxyConnector: SOCKS5 handshake complete", level: .info)
        
        return channel
    }
}

final class ManualSOCKS5Handler: ChannelDuplexHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    enum State {
        case initial
        case sentGreeting
        case sentRequest
        case connected
    }
    
    private var state: State = .initial
    private let targetHost: String
    private let targetPort: Int
    private let completionPromise: EventLoopPromise<Void>
    private var didComplete = false
    private var inboundBuffer: ByteBuffer?
    
    init(targetHost: String, targetPort: Int, completionPromise: EventLoopPromise<Void>) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.completionPromise = completionPromise
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            sendGreeting(context: context)
        }
    }
    
    func channelActive(context: ChannelHandlerContext) {
        if state == .initial {
            sendGreeting(context: context)
        }
        context.fireChannelActive()
    }
    
    private func sendGreeting(context: ChannelHandlerContext) {
        guard state == .initial else { return }
        Logger.log("SOCKS5: Sending greeting", level: .debug)
        // 1. Send SOCKS5 Greeting (Version 5, 1 Method, No Auth)
        var buffer = context.channel.allocator.buffer(capacity: 3)
        buffer.writeBytes([0x05, 0x01, 0x00])
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        state = .sentGreeting
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        if inboundBuffer == nil {
            inboundBuffer = context.channel.allocator.buffer(capacity: max(64, incoming.readableBytes))
        }
        inboundBuffer?.writeBuffer(&incoming)
        processInbound(context: context)
    }
    
    private func sendConnectRequest(context: ChannelHandlerContext) {
        Logger.log("SOCKS5: Sending connect request to \(targetHost):\(targetPort)", level: .debug)
        
        let hostBytes = Array(targetHost.utf8)
        let hostLen = hostBytes.count
        guard hostLen <= 255 else {
            let err = NSError(domain: "SOCKS5", code: 3, userInfo: [NSLocalizedDescriptionKey: "Target host is too long for SOCKS5 domain encoding (\(hostLen) bytes)"])
            fail(context: context, error: err)
            return
        }
        let capacity = 1 + 1 + 1 + 1 + 1 + hostLen + 2
        var buffer = context.channel.allocator.buffer(capacity: capacity)
        
        buffer.writeBytes([0x05, 0x01, 0x00, 0x03]) // SOCKS5, Connect, Reserved, DomainType
        buffer.writeInteger(UInt8(hostLen))
        buffer.writeBytes(hostBytes)
        buffer.writeInteger(UInt16(targetPort), endianness: .big)
        
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        state = .sentRequest
    }
    
    private func fail(context: ChannelHandlerContext, error: Error) {
        Logger.log("SOCKS5: Error - \(error.localizedDescription)", level: .error)
        completeOnceFail(error)
        context.close(promise: nil)
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(context: context, error: error)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        // If we buffered any bytes that arrived "too early" (e.g. SSH banner coalesced with the SOCKS reply),
        // flush them as soon as the SSH stack starts writing (a strong signal that its handlers are installed).
        if state == .connected, let buffer = inboundBuffer, buffer.readableBytes > 0 {
            inboundBuffer = nil
            context.fireChannelRead(wrapInboundOut(buffer))
        }
        context.write(data, promise: promise)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if !didComplete {
            let err = NSError(domain: "SOCKS5", code: 4, userInfo: [NSLocalizedDescriptionKey: "Proxy channel closed before SOCKS5 handshake completed"])
            completeOnceFail(err)
        }
        context.fireChannelInactive()
    }

    private func completeOnceSuccess() {
        guard !didComplete else { return }
        didComplete = true
        completionPromise.succeed(())
    }

    private func completeOnceFail(_ error: Error) {
        guard !didComplete else { return }
        didComplete = true
        completionPromise.fail(error)
    }

    private func processInbound(context: ChannelHandlerContext) {
        guard var buffer = inboundBuffer else { return }

        while true {
            switch state {
            case .sentGreeting:
                // Expect server choice: 0x05 0x00 (No Auth)
                guard buffer.readableBytes >= 2 else {
                    inboundBuffer = buffer
                    return
                }
                let version = buffer.readInteger(as: UInt8.self)
                let method = buffer.readInteger(as: UInt8.self)

                Logger.log("SOCKS5: Received greeting response ver=\(version ?? 0) method=\(method ?? 255)", level: .debug)

                if version == 0x05 && method == 0x00 {
                    sendConnectRequest(context: context)
                    // Continue loop; likely no more bytes yet.
                    continue
                } else {
                    let err = NSError(domain: "SOCKS5", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported Auth Method: \(String(describing: method))"])
                    inboundBuffer = buffer
                    fail(context: context, error: err)
                    return
                }

            case .sentRequest:
                // Expect server reply: 0x05 0x00 0x00 ATYP BND.ADDR BND.PORT
                guard buffer.readableBytes >= 4 else {
                    inboundBuffer = buffer
                    return
                }
                let version = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self)
                let reply = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self)
                let atyp = buffer.getInteger(at: buffer.readerIndex + 3, as: UInt8.self)

                var requiredLen = 4 // Base header
                switch atyp {
                case 0x01: requiredLen += 4 + 2 // IPv4
                case 0x04: requiredLen += 16 + 2 // IPv6
                case 0x03:
                    guard buffer.readableBytes >= 5 else {
                        inboundBuffer = buffer
                        return
                    }
                    let domainLen = Int(buffer.getInteger(at: buffer.readerIndex + 4, as: UInt8.self) ?? 0)
                    requiredLen += 1 + domainLen + 2
                default:
                    requiredLen = 4
                }

                guard buffer.readableBytes >= requiredLen else {
                    inboundBuffer = buffer
                    return
                }

                if version == 0x05 && reply == 0x00 {
                    Logger.log("SOCKS5: Connection established to target", level: .info)
                    state = .connected
                    buffer.moveReaderIndex(forwardBy: requiredLen)
                    completeOnceSuccess()
                    // Do not forward any leftover bytes here; SSH handlers may not be installed yet.
                    inboundBuffer = buffer
                    return
                } else {
                    let err = NSError(domain: "SOCKS5", code: 2, userInfo: [NSLocalizedDescriptionKey: "Connection Failed with code \(String(describing: reply))"])
                    inboundBuffer = buffer
                    fail(context: context, error: err)
                    return
                }

            case .connected:
                // After handshake, pass through future traffic.
                inboundBuffer = nil
                context.fireChannelRead(wrapInboundOut(buffer))
                return

            default:
                inboundBuffer = buffer
                return
            }
        }
    }
}

#!/usr/bin/env bash
# 用法: ./create_version.sh [版本号]
# 示例: ./create_version.sh 1.0.3  或  ./create_version.sh v1.0.3
# 会：拉取上游 → 打 tag → 推送到 origin 和 upstream

set -e

if [[ -z "$1" ]]; then
  echo "用法: $0 <版本号>"
  echo "示例: $0 1.0.3  或  $0 v1.0.3"
  exit 1
fi

RAW="$1"
# 统一成 vX.Y.Z 格式
if [[ "$RAW" == v* ]]; then
  TAG="$RAW"
else
  TAG="v$RAW"
fi

echo "版本号: $TAG"
read -p "确认创建并推送 tag $TAG? [y/N] " -n 1 -r
echo
if [[ ! "$REPLY" =~ ^[yY]$ ]]; then
  echo "已取消"
  exit 0
fi

# 当前分支
BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo ">>> 拉取上游..."
git fetch upstream 2>/dev/null || true

echo ">>> 若在 master 则与上游合并..."
if [[ "$BRANCH" == "master" ]]; then
  git merge upstream/master --no-edit 2>/dev/null || true
fi

echo ">>> 创建附注 tag: $TAG"
git tag -a "$TAG" -m "Release $TAG"

echo ">>> 推送到 origin..."
git push origin "$TAG"

echo ">>> 推送到 upstream（若无权限会报错，可忽略）..."
if git push upstream "$TAG" 2>/dev/null; then
  echo "已推送到 upstream"
else
  echo "未推送到 upstream（可能无写权限，仅已推到 origin）"
fi

echo ""
echo "完成. tag $TAG 已创建并推送。"

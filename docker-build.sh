#/bin/bash

TAG=$1
if [ -z "$TAG" ]; then
	TAG=1.27.2-vouch-proxy
fi

BASEDIR=`pwd`

echo "Building $TAG image"
docker buildx build --platform linux/amd64 -f Dockerfile.alpine -t yoldarz/nginx-proxy:$TAG --load .
echo "Pushing $TAG image to repository docker hub"
docker push yoldarz/nginx-proxy:$TAG
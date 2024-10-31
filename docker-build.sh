#/bin/bash

TAG=$1
if [ -z "$TAG" ]; then
	TAG=1.6.3
fi

BASEDIR=`pwd`

echo "Building $TAG image"
docker buildx build --platform linux/amd64 -f Dockerfile.alpine -t yoldarz/nginx-proxy:$TAG .
echo "Pushing $TAG image to repository"
docker push yoldarz/nginx-proxy:$TAG
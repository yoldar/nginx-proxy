#/bin/bash

BASEDIR=`pwd`

echo "Building latest image"
docker build -f Dockerfile -t yoldarz/nginx-proxy:latest .
echo "Pushing latest image to repository"
docker push yoldarz/nginx-proxy:latest
#!/bin/sh

cd frontend
npm i
npm run build

cd ../frontend-tui
CGO_ENABLED=0 go build -v -ldflags="-s -w" -o opinionated-installer-tui

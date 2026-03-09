#!/bin/bash

API="" # apigateway Invoke URL

hey -z 5s -c 20 -m POST \
-H "Content-Type: application/json" \
-d @payload.json \
$API
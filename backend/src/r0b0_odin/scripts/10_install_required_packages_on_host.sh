#!/bin/bash

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y cryptsetup debootstrap

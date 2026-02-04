#!/bin/bash

find . -type d -name .terraform | xargs rm -fr
find . -type f -name .terraform.lock.hcl | xargs rm

cp README.md README.new

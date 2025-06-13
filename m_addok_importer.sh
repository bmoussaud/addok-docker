#!/bin/bash
set -ex
echo "Addok import initialization...." 

ls -l /daily/gtm.json 
echo "Installing redis-tools..."
apt update -y 
apt install redis-tools -y 
echo "Testing Redis connection..."
redis-cli -h $REDIS_HOST ping 
if [ $? -ne 0 ]; then
    echo "Redis is not reachable. Please check your Redis configuration."
    exit 1
fi
echo "Redis is reachable. Proceeding with Addok import..."
addok batch /daily/gtm.json &
sleep 30
echo "Importing Addok data..."
addok ngrams 
sleep 30

echo "Addok import initialization completed."
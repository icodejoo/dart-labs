@echo off
git remote set-url origin let188@let188-ap-southeast-1.devops.alibabacloudcs.com:codeup/dart-labs.git
git remote set-url --add --push origin let188@let188-ap-southeast-1.devops.alibabacloudcs.com:codeup/dart-labs.git
git remote set-url --add --push origin https://github.com/icodejoo/dart-labs.git
echo Remotes configured:
git remote -v

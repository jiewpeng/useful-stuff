#!/bin/bash

TEMP_FOLDER=../__temp__
TEMP_ZIP_FILE=../repo_cleaned.zip
REPO=https://github.com/jiewpeng/test-git-clean.git

rm -rf $TEMP_FOLDER && \
rm -f $TEMP_ZIP_FILE && \
git clone $REPO $TEMP_FOLDER && \
cd $TEMP_FOLDER && \
# replace gitignore with stricter dockerignore
mv .gitignore gitignore && \
cp .dockerignore .gitignore && \
# remove everything from git tracking
git rm -r --cached . && \
# re-add everything, excluding those ignored in dockerignore (now gitignore)
git add .
# clean up files from dockerignore (now gitignore)
git clean -d -f -X && \
# restore original gitignore
rm .gitignore && \
mv gitignore .gitignore && \
zip -r $TEMP_ZIP_FILE . && \
# cleanup
rm -rf $TEMP_FOLDER
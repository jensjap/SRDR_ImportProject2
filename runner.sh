#!/bin/bash
FILES=/home/jensjap/Hive/Ruby/Rails/SRDR_ImportProject/Project_2/data/*.html
for f in $FILES
do
    ruby main.rb --file "$f"
done

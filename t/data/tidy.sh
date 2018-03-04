#!/bin/bash

if ! which perltidy > /dev/null 2>&1; then
    echo "No perltidy found, install it first!"
    exit 1
fi

find -name '*.tdy' -delete

find . \( -name '*.p[lm]' -o -name '*.t' \) -print0 | xargs -0 perltidy -sct -bbao -baao -nsfs -fbl -pt=2 -bt=2 -sbt=2 -l=120

while read file; do
    mv $file ${file%.tdy}
done < <(find . -name "*.tdy")

exit 0
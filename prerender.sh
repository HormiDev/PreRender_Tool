#!/bin/sh
echo -ne '\033c\033]0;PreRender_Tool\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/prerender.x86_64" "$@"

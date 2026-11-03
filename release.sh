#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
version=$(cat VERSION)
build=$(cat BUILD)
repo=heavensal/4431-IPTV-Macbook
test -z "$(git status --porcelain)" || { echo "Committez vos modifications avant de publier."; exit 1; }
./package-dmg.sh
asset="dist/4431-IPTV-Macbook-$version.dmg"
cp "dist/4431 IPTV.dmg" "$asset"
signature=$(Vendor/Sparkle/bin/sign_update --account 4431-IPTV-Macbook -p "$asset")
Vendor/Sparkle/bin/sign_update --account 4431-IPTV-Macbook --verify "$asset" "$signature"
python3 - "$version" "$build" "$asset" "$signature" <<'PY'
import sys, pathlib, xml.etree.ElementTree as ET
version, build, asset, signature = sys.argv[1:]
sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", sparkle)
rss = ET.Element("rss", version="2.0")
channel = ET.SubElement(rss, "channel")
ET.SubElement(channel, "title").text = "4431 IPTV"
item = ET.SubElement(channel, "item")
ET.SubElement(item, "title").text = "4431 IPTV " + version
ET.SubElement(item, "{"+sparkle+"}version").text = build
ET.SubElement(item, "{"+sparkle+"}shortVersionString").text = version
ET.SubElement(item, "{"+sparkle+"}minimumSystemVersion").text = "13.0"
ET.SubElement(item, "enclosure", {
    "url":f"https://github.com/heavensal/4431-IPTV-Macbook/releases/download/v{version}/{pathlib.Path(asset).name}",
    "length":str(pathlib.Path(asset).stat().st_size), "type":"application/octet-stream",
    "{"+sparkle+"}edSignature":signature})
ET.indent(rss)
ET.ElementTree(rss).write("appcast.xml", encoding="utf-8", xml_declaration=True)
PY
git push origin main
gh release create "v$version" "$asset" --repo "$repo" --target "$(git rev-parse HEAD)" --title "4431 IPTV pour Mac · $version" --notes-file RELEASE_NOTES.md --draft
git add appcast.xml
git commit -m "Publish update feed $version"
git push origin main
gh release edit "v$version" --repo "$repo" --draft=false --latest

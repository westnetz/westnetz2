#!/bin/sh

cd "`dirname $0`"/../python
${PYTHON} qos.py --spec /etc/westnetz.json > /usr/local/bin/qos.sh
chmod +x /usr/local/bin/qos.sh
/usr/local/bin/qos.sh

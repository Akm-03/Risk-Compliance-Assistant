#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/aria-env.sh"
CC_VERSION=1.0; CC_SEQ=1
POLICY="AND(OR('Org1MSP.peer','Org2MSP.peer'),'Org3MSP.peer')"

peer lifecycle chaincode package aria.tar.gz --path "$ARIA_ROOT/chaincode/aria-cc" --lang node --label ${CC_NAME}_${CC_VERSION}

for n in 1 2 3; do setOrg $n; peer lifecycle chaincode install aria.tar.gz; done

setOrg 1
PKG_ID=$(peer lifecycle chaincode queryinstalled | sed -n "s/^Package ID: \(.*\), Label: ${CC_NAME}_${CC_VERSION}\$/\1/p")
echo "package id: $PKG_ID"

for n in 1 2 3; do
  setOrg $n
  peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" \
    --channelID $CHANNEL --name $CC_NAME --version $CC_VERSION --package-id "$PKG_ID" \
    --sequence $CC_SEQ --signature-policy "$POLICY"
done

setOrg 1
peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL --name $CC_NAME --version $CC_VERSION \
  --sequence $CC_SEQ --signature-policy "$POLICY" --output json

peer lifecycle chaincode commit -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" \
  --channelID $CHANNEL --name $CC_NAME --version $CC_VERSION --sequence $CC_SEQ --signature-policy "$POLICY" \
  --peerAddresses localhost:7051 --tlsRootCertFiles "$(tls 1)" \
  --peerAddresses localhost:9051 --tlsRootCertFiles "$(tls 2)" \
  --peerAddresses localhost:11051 --tlsRootCertFiles "$(tls 3)"
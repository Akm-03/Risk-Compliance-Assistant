ARIA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ARIA_ROOT/fabric-samples/test-network"
export PATH=${PWD}/../bin:$PATH
export FABRIC_CFG_PATH=${PWD}/../config/
export CORE_PEER_TLS_ENABLED=true
export CHANNEL=aria-channel CC_NAME=aria
export ORDERER_CA=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

tls() { echo "${PWD}/organizations/peerOrganizations/org$1.example.com/peers/peer0.org$1.example.com/tls/ca.crt"; }

setOrg() {
  local n=$1 port
  case $n in 1) port=7051;; 2) port=9051;; 3) port=11051;; esac
  export CORE_PEER_LOCALMSPID=Org${n}MSP
  export CORE_PEER_TLS_ROOTCERT_FILE=$(tls $n)
  export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org$n.example.com/users/Admin@org$n.example.com/msp
  export CORE_PEER_ADDRESS=localhost:$port
}

# endorsed by a bank peer (Org1) and the regulator peer (Org3)
invokeAria() {
  peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" \
    -C $CHANNEL -n $CC_NAME \
    --peerAddresses localhost:7051 --tlsRootCertFiles "$(tls 1)" \
    --peerAddresses localhost:11051 --tlsRootCertFiles "$(tls 3)" -c "$1"
}
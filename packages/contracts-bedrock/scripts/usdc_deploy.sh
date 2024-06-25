DEPLOY_CONFIG_PATH="deploy-config/usdc-sepolia-devnet.json"
USDC_L1_ADDRESS=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
USDC_L2_ADDRESS=0x85977F663949E5AC21334F2219E2B4048EF74A80

# source .env for PRIVATE_KEY
source ../.env

export IMPL_SALT="avocado magnetico salato"

L1_VERIFIER_URL=https://eth-sepolia.blockscout.com/api\?
L2_VERIFIER_URL=https://sepolia-blockscout.lisk.com/api\?

# L1_RPC_URL=wss://ethereum-sepolia-rpc.publicnode.com
# L2_RPC_URL=https://rpc.sepolia-api.lisk.com

L1_RPC_URL=http://localhost:8545
L2_RPC_URL=http://localhost:8546

# outputs L2DedicatedBridgeProxy
forge script -vvv DeployDedicatedBridge.s.sol:DeployDedicatedBridge --sig 'deployL2DedicatedBridgeProxy()' --rpc-url "$L2_RPC_URL" --broadcast --private-key $PRIVATE_KEY
L2DedicatedBridgeProxy=$(cat ../deployments/4202-deploy.json | grep -Eo '"L2DedicatedBridgeProxy": "(\d*?,|.*?[^\\])"' | awk -F'"' '{print $4}' )

# outputs USDC_L1_BRIDGE_PROXY and USDC_L1_BRIDGE_DEPLOYMENT
forge script  -vvv DeployDedicatedBridge.s.sol:DeployDedicatedBridge $L2DedicatedBridgeProxy $USDC_L1_ADDRESS $USDC_L2_ADDRESS --sig 'runL1DedicatedBridgeDeployment(address,address,address)' --rpc-url "$L1_RPC_URL" --broadcast --private-key $PRIVATE_KEY
L1DedicatedBridgeProxy=$(cat ../deployments/11155111-deploy.json | grep -Eo '"L1DedicatedBridgeProxy": "(\d*?,|.*?[^\\])"' | awk -F'"' '{print $4}' )
L1DedicatedUSDCBridge=$(cat ../deployments/11155111-deploy.json | grep -Eo '"L1DedicatedUSDCBridge": "(\d*?,|.*?[^\\])"' | awk -F'"' '{print $4}' )


# outputs USDC_L2_BRIDGE_DEPLOYMENT
forge script -vvv DeployDedicatedBridge.s.sol:DeployDedicatedBridge  --sig 'deployL2DedicatedBridge()' --rpc-url "$L2_RPC_URL" --broadcast --private-key $PRIVATE_KEY
L2DedicatedBridge=$(cat ../deployments/4202-deploy.json | grep -Eo '"L2DedicatedBridge": "(\d*?,|.*?[^\\])"' | awk -F'"' '{print $4}' )

forge script -vvv DeployDedicatedBridge.s.sol:DeployDedicatedBridge $L2DedicatedBridgeProxy $L2DedicatedBridge $L1DedicatedBridgeProxy $USDC_L1_ADDRESS $USDC_L2_ADDRESS --sig 'initializeL2DedicatedBridge(address,address,address,address,address)' --rpc-url "$L2_RPC_URL" --broadcast --private-key $PRIVATE_KEY


# forge  verify-contract $USDC_L1_BRIDGE_DEPLOYMENT src/L1/L1DedicatedUSDCBridge.sol:L1DedicatedUSDCBridge --compiler-version 0.8.15 --rpc-url "$L1_RPC_URL"  --verifier blockscout --verifier-url $L1_VERIFIER_URL
# forge  verify-contract $USDC_L2_BRIDGE_DEPLOYMENT src/L2/L2DedicatedBridge.sol:L2DedicatedBridge --compiler-version 0.8.15 --rpc-url "$L2_RPC_URL"  --verifier blockscout --verifier-url $L2_VERIFIER_URL




echo "All done!"
echo "L1DedicatedBridgeProxy", $L1DedicatedBridgeProxy
echo "L1DedicatedUSDCBridge", $L1DedicatedUSDCBridge
echo "L2DedicatedBridgeProxy", $L2DedicatedBridgeProxy
echo "L2DedicatedBridge", $L2DedicatedBridge

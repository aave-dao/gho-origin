import Safe from '@safe-global/protocol-kit';
import SafeApiKit from '@safe-global/api-kit';
import {OperationType, MetaTransactionData} from '@safe-global/types-kit';
import {parseAbi, encodeFunctionData} from 'viem';
import {createRequire} from 'module';

const require = createRequire(import.meta.url);
const TransportNodeHid = require('@ledgerhq/hw-transport-node-hid').default;
const Eth = require('@ledgerhq/hw-app-eth').default;

async function main() {
  const RPC_URL = 'https://monad-mainnet.g.alchemy.com/v2/<KEY>';
  const CHAIN_ID = 143n; // Update with whatever network!!!
  const SAFE_ADDRESS = '<SAFE>>';
  const SAFE_MIGRATION = '0x526643F69b81B008F46d95CD5ced5eC0edFFDaC6'; // CHECK BUT USUALLY THIS IS THE SAFE MIGRATION ADDRESS ON ALL NETWORKS
  const DERIVATION_PATH = "44'/60'/1'/0/0"; // LEDGER LIVE ONLY! METAMTASK IS DIFF

  const transport = await TransportNodeHid.create();
  const eth = new Eth(transport);
  const {address: signerAddress} = await eth.getAddress(DERIVATION_PATH, false);
  console.log('Signing as:', signerAddress); // must equal your registered proposer

  const ABI = parseAbi(['function migrateL2WithFallbackHandler() external']);
  const data = encodeFunctionData({abi: ABI, functionName: 'migrateL2WithFallbackHandler'});
  const safeTx: MetaTransactionData = {
    to: SAFE_MIGRATION,
    value: '0',
    data,
    operation: OperationType.DelegateCall,
  };

  const protocolKit = await Safe.init({provider: RPC_URL, safeAddress: SAFE_ADDRESS});
  const nonce = await protocolKit.getNonce();
  const tx = await protocolKit.createTransaction({transactions: [safeTx], options: {nonce}});
  const safeTxHash = await protocolKit.getTransactionHash(tx);

  console.log('Confirm on your Ledger…');
  const sig = await eth.signPersonalMessage(DERIVATION_PATH, safeTxHash.slice(2));

  const baseV = typeof sig.v === 'number' ? sig.v : parseInt(sig.v, 16);
  const signature = '0x' + sig.r + sig.s + (baseV + 4).toString(16).padStart(2, '0');

  const apiKit = new SafeApiKit({
    chainId: CHAIN_ID,
    apiKey: process.env.SAFE_TRANSACTION_SERVICE_API_KEY,
  });
  await apiKit.proposeTransaction({
    safeAddress: SAFE_ADDRESS,
    safeTransactionData: tx.data,
    safeTxHash,
    senderAddress: signerAddress,
    senderSignature: signature,
  });

  console.log('Proposed. safeTxHash:', safeTxHash);
  await transport.close();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

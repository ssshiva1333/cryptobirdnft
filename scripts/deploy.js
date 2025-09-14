// scripts/deploy.js  (CommonJS, ethers v6)
require('dotenv/config');
const fs = require('fs/promises');
const path = require('path');
const { JsonRpcProvider, Wallet, ContractFactory, NonceManager } = require('ethers');

async function loadArtifact() {
  const candidates = [
    // If you compiled with the solc script:
    path.join(__dirname, '..', 'artifacts', 'CryptoBirdsContract.json'),
    // If you compiled with Hardhat:
    path.join(__dirname, '..', 'artifacts', 'contracts', 'CryptoBirdsContract.sol', 'CryptoBirdsContract.json'),
  ];
  for (const p of candidates) {
    try {
      const json = await fs.readFile(p, 'utf8');
      return JSON.parse(json);
    } catch (_) {}
  }
  throw new Error(
    'Artifact not found.\n' +
    'Run one of:\n' +
    '  node scripts/compile.js    (solc)\n' +
    'or\n' +
    '  npx hardhat compile        (Hardhat)\n'
  );
}

(async () => {
  const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:8545';
  const PK = process.env.PRIVATE_KEY;
  if (!PK) throw new Error('Missing PRIVATE_KEY in .env');

  const provider = new JsonRpcProvider(RPC_URL);
  const wallet = new Wallet(PK, provider);
  const signer = new NonceManager(wallet); // handles nonces safely

  const deployer = await signer.getAddress();
  const balance = await provider.getBalance(deployer);

  console.log('RPC:', RPC_URL);
  console.log('Deployer:', deployer);
  console.log('Balance:', balance.toString());

  const { abi, bytecode } = await loadArtifact();
  const bytecodeHex = bytecode.startsWith('0x') ? bytecode : `0x${bytecode}`;

  const factory = new ContractFactory(abi, bytecodeHex, signer);

  const contract = await factory.deploy(); // ethers auto-estimates gas
  console.log('Deploy tx hash:', contract.deploymentTransaction().hash);

  const address = await contract.getAddress(); // waits for deployment
  console.log('✓ Deployed at:', address);

  // Optional: sanity mint to deployer (EOA); NonceManager avoids "nonce too low"
  const mintTx = await contract.safeMint(deployer, 'ipfs://cryptobirds/1');
  await mintTx.wait();
  console.log('✓ Minted token #1 to deployer');

  // Example: read back owner & tokenURI
  const owner = await contract.ownerOf(1n);
  const uri = await contract.tokenURI(1n);
  console.log('Token #1 owner:', owner);
  console.log('Token #1 URI  :', uri);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

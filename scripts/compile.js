const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const solc = require('solc');

(async () => {
  const SRC = 'contracts/CryptoBirdsContract.sol';
  const OUT_DIR = 'artifacts';
  const CONTRACT_NAME = 'CryptoBirdsContract';

  const source = await fsp.readFile(SRC, 'utf8');
  const input = {
    language: 'Solidity',
    sources: { [path.basename(SRC)]: { content: source } },
    settings: {
      optimizer: { enabled: true, runs: 200 },
      outputSelection: { '*': { '*': ['abi','evm.bytecode.object'] } },
    },
  };

  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  if (output.errors && output.errors.length) {
    const fatal = output.errors.filter(e => e.severity === 'error');
    if (fatal.length) {
      console.error(output.errors);
      process.exit(1);
    } else {
      console.warn(output.errors);
    }
  }

  const fileKey = path.basename(SRC);
  const c = output.contracts[fileKey][CONTRACT_NAME];
  await fsp.mkdir(OUT_DIR, { recursive: true });
  await fsp.writeFile(
    path.join(OUT_DIR, `${CONTRACT_NAME}.json`),
    JSON.stringify({ abi: c.abi, bytecode: c.evm.bytecode.object }, null, 2),
    'utf8'
  );
  console.log(`✓ Compiled -> artifacts/${CONTRACT_NAME}.json`);
})();

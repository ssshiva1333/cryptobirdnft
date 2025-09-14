it is an erc721 project which handles a single nft collection

npm init -y
npm install --save-dev hardhat
npx hardhat
npm install ethers@6 dotenv
npx hardhat compile
npx hardhat node
node scripts/deploy.js
npx serve .

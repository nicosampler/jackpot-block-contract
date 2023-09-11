import * as dotenv from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";

dotenv.config();

let accounts: any[] = [];
if (process.env.PRIVATE_KEY !== undefined) {
  accounts = [process.env.PRIVATE_KEY];
} else {
  throw new Error(`PRIVATE_KEY not set`);
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    artifacts: "./artifacts",
    sources: "./src",
  },
  networks: {
    goerli: {
      url: process.env.GOERLI_URL || "",
      accounts: accounts,
      timeout: 100000,
      //  gasPrice: 400000000000,
    },
    gnosis: {
      url: process.env.GNOSIS_URL || "",
      accounts: accounts,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.YOUR_ETHERSCAN_API_KEY,
  },
};

export default config;

import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-deploy";

dotenv.config();

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    sender: { default: 1 },
    recipient: { default: 2 },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    pharosdev: {
      url: "https://devnet.dplabs-internal.com",
      accounts: [process.env.PRIVATE_KEY2 || ""],
      chainId: 50002,
      gas: 5000000,
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
    //gasPrice: 100,
  },
};

export default config;

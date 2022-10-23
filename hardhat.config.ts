import * as dotenv from "dotenv";
dotenv.config();
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
	defaultNetwork: "localhost",
	networks: {
		localhost: {
			from: "http://127.0.0.1:8545/",
		}
	},
	solidity: {
		compilers: [
			{ 
				version: "0.5.16",
				settings:{
					optimizer:{
						enabled: true,
						runs: 200
					}
				}
			},
			{ version: "0.8.10" },
		]
	},

};

export default config;

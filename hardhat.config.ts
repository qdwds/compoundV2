import * as dotenv from "dotenv";
dotenv.config();
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";


const config: HardhatUserConfig = {
	defaultNetwork: "localhost",
	networks: {
		localhost: {
			from: "http://127.0.0.1:8545/",
			// accounts:[process.env.GRANACHE_PRIVATE_KEY!]
		},
		oke:{
			url:"https://exchaintestrpc.okex.org",
			accounts:[process.env.OKE_PRIVATE_KEY!]
		},
		matic:{
			url:"https://polygon-testnet.public.blastapi.io",
			accounts:[process.env.OKE_PRIVATE_KEY!]
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

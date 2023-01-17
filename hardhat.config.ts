import * as dotenv from "dotenv";
dotenv.config();
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";


const config: HardhatUserConfig = {
	defaultNetwork: "localhost",
	networks: {
		localhost: {
			from: "http://127.0.0.1:8545/",
				// mining: {	//	开启自动挖矿
				//   auto: false,
				//   interval: [500, 1000],	//	0.5s - 1s 随机时间创建区块
				// }
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

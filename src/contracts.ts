import * as dotenv from "dotenv";
dotenv.config();
import { ethers } from "hardhat"
import address from "../abi/address.json";


export const createContracts = async () => {
    const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545/");
    // const wallet = new ethers.Wallet(process.env.HARDHAT_PRIVATE_KEY!);
    // const signer = wallet.connect(provider);
    const signers = await ethers.getSigners();
    const signer = signers[0]
    const compoundG7  = await ethers.getContractAt("ComptrollerG7", address.comptrollerG7, signer);
    const cErc20Delegator = await ethers.getContractAt("CErc20Delegator", address.cErc20Delegator, signer);
    const erc20Token = await ethers.getContractAt("ERC20Token", address.erc20Token, signer);
    
    return{
        signer,
        compoundG7,
        cErc20Delegator,
        erc20Token,
    }
}
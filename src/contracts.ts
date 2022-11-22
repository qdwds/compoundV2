import * as dotenv from "dotenv";
dotenv.config();
import { ethers } from "hardhat"
import address from "../abi/address.json";


export const createContracts = async ():Promise<any> => {
    // const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545/");
    // const wallet = new ethers.Wallet(process.env.OKE_PRIVATE_KEY!);
    // const signer = wallet.connect(provider);
    const signers = await ethers.getSigners();
    const account = signers[1];
    const signer = signers[0];
    const comptroller  = await ethers.getContractAt("ComptrollerG7", address.comptroller, signer);
    const cErc20Delegator = await ethers.getContractAt("CErc20Delegator", address.cErc20Delegator, signer);
    const erc20Token = await ethers.getContractAt("ERC20Token", address.erc20Token, signer);
    const accountERC20 = await ethers.getContractAt("ERC20Token", address.erc20Token, account);
    const accountCToken = await ethers.getContractAt("CErc20Delegator", address.cErc20Delegator, account);
    return{
        signer,
        comptroller,
        cErc20Delegator,
        erc20Token,

        
        account,
        accountCToken,
        accountERC20,
    }
}
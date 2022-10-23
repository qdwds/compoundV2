import * as dotenv from "dotenv";
dotenv.config();
import { ethers } from "ethers"
import { info as g7info, abi as g7abi } from "../abi/ComptrollerG7.json"
export const createContracts = async () => {
    const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545/");
    console.log(process.env.HARDHAT_PRIVATE_KEY)
    const wallet = new ethers.Wallet(process.env.HARDHAT_PRIVATE_KEY!);
    const signer = wallet.connect(provider);

    const compoundG7  = new ethers.Contract(g7info.name, g7abi, signer);


    return{
        compoundG7
    }
}
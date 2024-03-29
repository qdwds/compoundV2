import * as dotenv from "dotenv";
dotenv.config();
import { ethers } from "hardhat"
import address from "../abi/address.json";


export const createContracts = async (): Promise<any> => {
    // const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545/");
    // const wallet = new ethers.Wallet(process.env.OKE_PRIVATE_KEY!);
    // const signer = wallet.connect(provider);
    const signers = await ethers.getSigners();
    const account = signers[1];
    const signer = signers[0];
    const comptroller = await ethers.getContractAt("Comptroller", address.comptroller, signer);
    const cErc20Delegator = await ethers.getContractAt("CErc20Delegator", address.cErc20Delegator, signer);
    const erc20Token = await ethers.getContractAt("ERC20Token", address.erc20Token, signer);
    const accountERC20 = await ethers.getContractAt("ERC20Token", address.erc20Token, account);
    const accountCToken = await ethers.getContractAt("CErc20Delegator", address.cErc20Delegator, account);
    const oracle = await ethers.getContractAt("SimplePriceOracle", address.simplePriceOracle, signer);
    const cEther = await ethers.getContractAt("SimplePriceOracle", address.cEther, signer);
    const comp = await ethers.getContractAt("Comp", address.comp, signer);
    const cUSDT = await ethers.getContractAt("CErc20Delegator", address.cUSDT, signer);
    const cDAI = await ethers.getContractAt("CErc20Delegator", address.cDAI, signer);
    const usdt = await ethers.getContractAt("USDTToken",address.usdt, signer);
    const dai = await ethers.getContractAt("DAIToken",address.dai, signer);
    return {
        signer,
        comptroller,
        cErc20Delegator,
        erc20Token,
        oracle,
        cEther,
        account,
        accountCToken,
        accountERC20,
        comp,
        usdt,
        cUSDT,
        dai,
        cDAI,
    }
}
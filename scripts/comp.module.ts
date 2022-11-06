import type { Contract } from "ethers";
import { ethers } from "hardhat";
import { readFile, writeFile } from "fs";
import { join } from "path";
import { contractAbi } from "../utils/contractInfo";

/**
 * @module comp token module
 */


export const compTokenDeploy = async():Promise<Contract>=>{
    const name ="Comp";
    const Comp = await ethers.getContractFactory(name);
    const commp = await Comp.deploy("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    await commp.deployed();
    await contractAbi(commp.address, name);
    return commp;
}


export const setCompAddress = async (address:string) => {
    const path = join(__dirname,"../contracts/Comptroller.sol");
    readFile(path,"utf-8",(err, data)=>{
        if(err != null)return console.log(err);
        const context = data.replace(/\/\*\*start\*\/(\S+)\/\*\*end\*\//,`/**start*/${address}/**end*/`)
        writeFile(path, context, err => {
            if(err != null) return console.log(err);
            console.log("change comp address success !");
        })
    })
}

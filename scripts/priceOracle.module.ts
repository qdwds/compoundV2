// 代理合约

import { BigNumber, Signer } from "ethers";
import { formatEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { contractAbi } from "../utils/contractInfo";

const simplePriceOracleName = "SimplePriceOracle";

// 预言机
export const simplePriceOracleDeploy = async () => {
    const SimplePriceOracle = await ethers.getContractFactory(simplePriceOracleName);
    const simplePriceOracle = await SimplePriceOracle.deploy();
    await simplePriceOracle.deployed();
    await contractAbi(simplePriceOracle.address, simplePriceOracleName);
    return simplePriceOracle;
}

// 设置市场价格
export const simplePriceOracle_setUnderlyingPrice = async (signer:Signer,simplePriceOracleAddress: string, cToken: string, underlyingPriceMantissa: BigNumber) => {
    const simple = await ethers.getContractAt(simplePriceOracleName, simplePriceOracleAddress, signer);
    // 部署cEth 消耗gas比较多
    await simple.setUnderlyingPrice(cToken, underlyingPriceMantissa, { gasLimit: 3000000 }).catch(err => console.log(err));
    // await simple.setUnderlyingPrice(cToken, underlyingPriceMantissa).catch(err => console.log(err));
    console.log(`simplePriceOracle_setUnderlyingPrice call success ${cToken} ${formatEther(underlyingPriceMantissa)}$ !!`)
}
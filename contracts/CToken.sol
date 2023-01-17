pragma solidity ^0.5.16;

import "./ComptrollerInterface.sol";
import "./CTokenInterfaces.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";
import "./EIP20Interface.sol";
import "./InterestRateModel.sol";
import "hardhat/console.sol";



/**
* @title Compound 的 CToken 合约
* @notice CTokens 的抽象基础
* @author 复合
*/
// ctoken  基类合约
contract CToken is CTokenInterface, Exponential, TokenErrorReporter {
    /**
    * @notice 初始化货币市场
    * @param comptroller_ 主计长地址
    * @param interestRateModel_ 利率模型的地址
    * @param initialExchangeRateMantissa_ 初始汇率，按 1e18 缩放
    * @param name_ 此令牌的 EIP-20 名称
    * @param symbol_ 此令牌的 EIP-20 符号
    * @param decimals_ 此令牌的 EIP-20 十进制精度
    */
    // 用来初始化合约，设置审计合约和利率模型
    function initialize(
        ComptrollerInterface comptroller_,  //  审计合约
        InterestRateModel interestRateModel_,   //  利率模型合约
        uint initialExchangeRateMantissa_,  //  利率小数
        string memory name_,    //  名字
        string memory symbol_,  //  符号
        uint8 decimals_     //  小数
    ) public {
        // 判断是否为管理员
        require(msg.sender == admin, "only admin may initialize the market");
        
        // 市场只能初始化一次
        // 校验 上一次计算利息区块和市场开放以来的累计值 都为0
        // console.log("accrualBlockNumber", accrualBlockNumber);
        // console.log("borrowIndex", borrowIndex);
        require(accrualBlockNumber == 0 && borrowIndex == 0, "market may only be initialized once");

        // 通过传入的利率来 设置初始汇率
        initialExchangeRateMantissa = initialExchangeRateMantissa_;
        // console.log("initialExchangeRateMantissa", initialExchangeRateMantissa);
        // 利率必须大于0
        require(initialExchangeRateMantissa > 0, "initial exchange rate must be greater than zero.");

        // Set the comptroller
        // 设置新的cToken 控制器，成功会返回没有错误(Error.NO_ERROR);
        uint err = _setComptroller(comptroller_);
        // 确保控制器修改成功
        require(err == uint(Error.NO_ERROR), "setting comptroller failed");

        // Initialize block number and borrow index (block number mocks depend on comptroller being set)
        //  获取当前区块
        accrualBlockNumber = getBlockNumber();
        // 设置 利率累计值 默认为 1e18
        borrowIndex = mantissaOne;

        // 设置利率模型（取决于区块数/借款指数）
        err = _setInterestRateModelFresh(interestRateModel_);
        // 确保返回成功
        require(err == uint(Error.NO_ERROR), "setting interest rate model failed");

        name = name_;
        symbol = symbol_;
        decimals = decimals_;

        // The counter starts true to prevent changing it from zero to non-zero (i.e. smaller cost/refund)
        // 计数器开始为真以防止将其从零更改为非零（即较小的成本/退款）
        // 防止重入攻击？
        _notEntered = true;
    }

    /**
    * @notice 通过 `spender` 将 `tokens` 令牌从 `src` 转移到 `dst`
    * @dev 在内部由 `transfer` 和 `transferFrom` 调用
    * @param spender 执行转账的账户地址
    * @param src 源账号地址
    * @param dst 目标账户的地址
    * @param tokens 要转移的代币数量
    */
    // * @return 传输是否成功

    function transferTokens(
        address spender,    //  发送者
        address src,        //  来源
        address dst,        //  目标地址
        uint tokens         //  转账数量
    ) internal returns (uint) {
        /* Fail if transfer not allowed */
        // 通过控制器发起转账
        uint allowed = comptroller.transferAllowed(address(this), src, dst, tokens);
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.TRANSFER_COMPTROLLER_REJECTION, allowed);
        }

        /* Do not allow self-transfers */
        // 两个address 不能相等
        if (src == dst) {
            return fail(Error.BAD_INPUT, FailureInfo.TRANSFER_NOT_ALLOWED);
        }

        /* Get the allowance, infinite for the account owner */
        // 授权数量
        uint startingAllowance = 0;
        // 授权无限
        if (spender == src) {
            startingAllowance = uint(-1);
        } else {
            // 转移
            startingAllowance = transferAllowances[src][spender];
        }

        /* Do the calculations, checking for {under,over}flow */
        MathError mathErr;
        uint allowanceNew;
        uint srcTokensNew;
        uint dstTokensNew;
        // allowanceNew = startingAllowance - 转移的数量  
        (mathErr, allowanceNew) = subUInt(startingAllowance, tokens);
        if (mathErr != MathError.NO_ERROR) {
            return fail(Error.MATH_ERROR, FailureInfo.TRANSFER_NOT_ALLOWED);
        }
        // srcTokensNew = src余额 - 转移的数量
        (mathErr, srcTokensNew) = subUInt(accountTokens[src], tokens);
        if (mathErr != MathError.NO_ERROR) {
            return fail(Error.MATH_ERROR, FailureInfo.TRANSFER_NOT_ENOUGH);
        }
        // dstTokensNew = dst余额 - 转移的数量
        (mathErr, dstTokensNew) = addUInt(accountTokens[dst], tokens);
        if (mathErr != MathError.NO_ERROR) {
            return fail(Error.MATH_ERROR, FailureInfo.TRANSFER_TOO_MUCH);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        // 更新余额
        accountTokens[src] = srcTokensNew;
        accountTokens[dst] = dstTokensNew;

        /* Eat some of the allowance (if necessary) */
        // 授权额度 != 无限大 === 最新的授权额度
        if (startingAllowance != uint(-1)) {
            transferAllowances[src][spender] = allowanceNew;
        }

        /* We emit a Transfer event */
        emit Transfer(src, dst, tokens);

        // unused function
        // comptroller.transferVerify(address(this), src, dst, tokens);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint256 amount) external nonReentrant returns (bool) {
        return transferTokens(msg.sender, msg.sender, dst, amount) == uint(Error.NO_ERROR);
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address src, address dst, uint256 amount) external nonReentrant returns (bool) {
        return transferTokens(msg.sender, src, dst, amount) == uint(Error.NO_ERROR);
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        address src = msg.sender;
        transferAllowances[src][spender] = amount;
        emit Approval(src, spender, amount);
        return true;
    }

    /**
     * @notice Get the current allowance from `owner` for `spender`
     * @param owner The address of the account which owns the tokens to be spent
     * @param spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (-1 means infinite)
     */
    function allowance(address owner, address spender) external view returns (uint256) {
        return transferAllowances[owner][spender];
    }

    /**
      * @notice 获取`owner`的代币余额
      * @param owner 要查询的账户地址
      * @return `owner` 拥有的代币数量
      */
    // 当前账户的存款余额
    function balanceOf(address owner) external view returns (uint256) {
        return accountTokens[owner];
    }

    /**
      * @notice 获取`owner`的底层余额
      * @dev 这也会在交易中产生利息
      * @param owner 要查询的账户地址
      */
    //   * @return `owner` 拥有的底层证券数量
    // 基础资金余额 =  供应余额
    // 获取标的资产的数量
    function balanceOfUnderlying(address owner) external returns (uint) {
        // 获取最新汇率
        Exp memory exchangeRate = Exp({mantissa: exchangeRateCurrent()});
        // console.log("exchangeRate 最新汇率", exchangeRate.mantissa);
        // 最新汇率  用户余额
        (MathError mErr, uint balance) = mulScalarTruncate(exchangeRate, accountTokens[owner]);
        // console.log("balance", balance);
        require(mErr == MathError.NO_ERROR, "balance could not be calculated");
        console.log("balance",balance);
        emit BalanceOfUnderlying(balance);  //  自己添加事件 获取额度
        return balance;
    }

    /**
    * @notice 获取账户余额的快照，以及缓存的汇率 获取用户余额和汇率
    * @dev 这被主计长用来更有效地执行流动性检查。
    * @param account 要快照的账户地址
    */
    // * @return（可能的错误，cToken代币余额，借入余额，汇率尾数）
    // 获取当前用户的 cToken额度  借款额度 汇率
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint) {
        // 用户余额
        uint cTokenBalance = accountTokens[account];
        // console.log("cTokenBalance", cTokenBalance);
        uint borrowBalance; //  当前用户借款额度
        uint exchangeRateMantissa;  //  当前用户的存款汇率

        MathError mErr;

        // 获取用户借款额度
        (mErr, borrowBalance) = borrowBalanceStoredInternal(account);
        // console.log("borrowBalance 用户借款额度", borrowBalance);
        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0, 0, 0);
        }
        // 获取存款汇率
        (mErr, exchangeRateMantissa) = exchangeRateStoredInternal();
        // console.log("exchangeRateMantissa 存款汇率", exchangeRateMantissa);
        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0, 0, 0);
        }

        // console.log("exchangeRateMantissa",exchangeRateMantissa);
        return (
            uint(Error.NO_ERROR), 
            cTokenBalance, //   CTOKEN 额度
            borrowBalance,  //  借款额度
            exchangeRateMantissa    // 汇率
        );
    }

   /**
    * @dev 返回当前调用的区块号
    * 这主要是为了继承测试合约来存根这个结果。
    */
    function getBlockNumber() internal view returns (uint) {
        return block.number;
    }

    /**
    * @notice 返回此cToken的当前每块借款利率
    */
    // * @return 每块贷款利率，按1e18缩放
    // 每个区块的借款汇率
    function borrowRatePerBlock() external view returns (uint) {
        // 调用传入利率模型合约的方法计算 借款利率  资金池余额 总借入  总储备量
        return interestRateModel.getBorrowRate(getCashPrior(), totalBorrows, totalReserves);
    }

    /**
    * @notice 返回此cToken的当前每块供应利率 ? 供应利率？？
    */
    // * @return 每个区块的供应利率，按1e18缩放
    //  每个区块的存款利率
    function supplyRatePerBlock() external view returns (uint) {
        // 调用传入利率模型合约的方法计算 还款利率 总借入  总储备量 市场储备资金
        // console.log("reserveFactorMantissa", reserveFactorMantissa);
        return interestRateModel.getSupplyRate(getCashPrior(), totalBorrows, totalReserves, reserveFactorMantissa);
    }

    /**
    * @notice 返回当前借款总额加上应计利息
    * nonReentrant 防止重入攻击
    */
    // * @return 利息借款总额
    //  当前借款总额度  = 借款额度 + 应付利息
    // function totalBorrowsCurrent() external  returns (uint) {
    function totalBorrowsCurrent() external nonReentrant returns (uint) {
        // 计算累积列率时候不能报错
        require(accrueInterest() == uint(Error.NO_ERROR), "accrue interest failed");
        // console.log("totalBorrows", totalBorrows);
        return totalBorrows;
    }

    /**
    * @notice 将利息累积到更新的borrowIndex，然后使用更新的borlowIndex计算账户的借款余额
    * @param account 更新borrowIndex后应计算其余额的地址
    */
    // * @return 计算的余额
    // 用户借款额度包含利息 借钱肯定借的是基础资产(标的资产)
    // function borrowBalanceCurrent(address account) external returns (uint) {
    function borrowBalanceCurrent(address account) external nonReentrant returns (uint) {
        // 计算累积利率
        require(accrueInterest() == uint(Error.NO_ERROR), "accrue interest failed");
        // 借款人借入额度
        return borrowBalanceStored(account);
    }

    /**
    * @notice 根据存储的数据返回账户的借款余额 返回用户借款额度
    * @param account 应计算其余额的地址
    */
    // * @return 计算的余额
    //  借款人借入额度 包含利息
    function borrowBalanceStored(address account) public view returns (uint) {
        // 获取借款额度
        (MathError err, uint result) = borrowBalanceStoredInternal(account);
        require(err == MathError.NO_ERROR, "borrowBalanceStored: borrowBalanceStoredInternal failed");
        console.log("借款额度：", result);
        return result;
    }

    /**
    * @notice 根据存储的数据返回账户的借入余额  当前账户借款额度
    * @param account 需要计算余额的地址
    */
//    @return（错误代码，计算的余额，如果错误代码非零，则为 0）
    function borrowBalanceStoredInternal(address account) internal view returns (MathError, uint) {
        /* Note: we do not assert that the market is up to date */
        MathError mathErr;
        uint principalTimesIndex;   //  时间指数
        uint result;    //  借款额度

        // /* Get borrowBalance and borrowIndex */
        // 获取用户借款余额和借款指数
        BorrowSnapshot storage borrowSnapshot = accountBorrows[account];
        // console.log("borrowSnapshot.principal", borrowSnapshot.principal);
        // console.log("borrowSnapshot.principal", borrowSnapshot.interestIndex);
        /* If borrowBalance = 0 then borrowIndex is likely also 0.
         * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
         */
        // 借款额度 == 0 返回 0
        if (borrowSnapshot.principal == 0) {
            return (MathError.NO_ERROR, 0);
        }

        /* 使用利率指数计算新的借款余额：
        * recentBorrowBalance = borrower.borrowBalance *market.borrowIndex /borrower.borrowIndex
        */
        (mathErr, principalTimesIndex) = mulUInt(borrowSnapshot.principal, borrowIndex);
        if (mathErr != MathError.NO_ERROR) {
            return (mathErr, 0);
        }

        (mathErr, result) = divUInt(principalTimesIndex, borrowSnapshot.interestIndex);
        if (mathErr != MathError.NO_ERROR) {
            return (mathErr, 0);
        }
        console.log("当前账户借款额度",result);
        return (MathError.NO_ERROR, result);
    }

    /**
    * @notice 累积利息然后返回最新汇率
    */
    // * @return 按 1e18 比例计算的汇率
    //  cToken <-> token 兑换率
    // function exchangeRateCurrent() public returns (uint) {
    function exchangeRateCurrent() public nonReentrant returns (uint) {
        // 计算累积利率 没有报错
        require(accrueInterest() == uint(Error.NO_ERROR), "accrue interest failed");
        // 返回cToken的汇率
        return exchangeRateStored();
    }

    /**
    * @notice 计算从底层证券到 CToken 的汇率 
    * @dev 这个函数在计算汇率之前不会产生利息
    外部使用 返回存储汇率
    */
    //  cToken <-> token 兑换率
    // * @return 按 1e18 比例计算的汇率
    function exchangeRateStored() public view returns (uint) {
        (MathError err, uint result) = exchangeRateStoredInternal();
        require(err == MathError.NO_ERROR, "exchangeRateStored: exchangeRateStoredInternal failed");
        return result;
    }

    /**
    * @notice 计算从底层证券到 CToken 的汇率
    * @dev 这个函数在计算汇率之前不会产生利息
    */
    // * @return（错误代码，计算的汇率按 1e18 缩放）
    //  cToken <-> token 兑换率
    function exchangeRateStoredInternal() internal view returns (MathError, uint) {
        // 获取流通的代币总量   质押流通总数？？？？？
        uint _totalSupply = totalSupply;
        // 首次创建 返回汇率为0
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            // 返回 默认汇率 == 0
            return (MathError.NO_ERROR, initialExchangeRateMantissa);
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
             */
            // 获取资金池 余额
            uint totalCash = getCashPrior();
            console.log("资金池余额",totalCash);
            uint cashPlusBorrowsMinusReserves;
            Exp memory exchangeRate;
            MathError mathErr;
            // console.log("totalCash", totalCash);
            // console.log("totalBorrows", totalBorrows);
            // console.log("totalReserves", totalReserves);
            //  totalCash + totalBorrows - totalReserves
            // 资金池余额 + 借款总量 - 总储备量

            // 现金加借贷减储备  = totalCash(资金池余额) + totalBorrows(市场总借款额度) - totalReserves(资产储备金总额)
            (mathErr, cashPlusBorrowsMinusReserves) = addThenSubUInt(totalCash, totalBorrows, totalReserves);
            if (mathErr != MathError.NO_ERROR) {
                return (mathErr, 0);
            }
            // console.log("cashPlusBorrowsMinusReserves", cashPlusBorrowsMinusReserves);
            // 流通量总数
            // 存款利率 = 现金加借贷减储备 / 流通代币总数
            (mathErr, exchangeRate) = getExp(cashPlusBorrowsMinusReserves, _totalSupply);
            if (mathErr != MathError.NO_ERROR) {
                return (mathErr, 0);
            }
            console.log("cToken 兑换率", exchangeRate.mantissa);
            return (MathError.NO_ERROR, exchangeRate.mantissa);
        }
    }

    /**
      * @notice 获取该cToken在标的资产中的现金余额
      */
    //   * @return 该合约拥有的标的资产数量
    function getCash() external view returns (uint) {
        return getCashPrior();
    }

    /**
    * @notice 将应计利息应用于总借款和准备金
    * @dev 这计算从最后一个检查点块产生的利息
    *直到当前块并将新的检查点写入存储。
    */
    // 计算 累计利率     借款利率
    // 计算总利息
    function accrueInterest() public returns (uint) {
        /* Remember the initial block number */
        // 获取当前区块
        uint currentBlockNumber = getBlockNumber();
        // 最近一次计算的区块
        uint accrualBlockNumberPrior = accrualBlockNumber;

        /* Short-circuit accumulating 0 interest */
        // 当前区块 == 最近一次计算的区块相等的话 表示当前区块已经计算过利息
        if (accrualBlockNumberPrior == currentBlockNumber) {
            return uint(Error.NO_ERROR);
        }

        /* Read the previous values out of storage */
        // 地秤资产余额，总借款，总储备金，借款指数
        // 资金池剩余的标的资产余额
        uint cashPrior = getCashPrior();
        // 之前借款额度 总借款额度
        uint borrowsPrior = totalBorrows;
        // 之前储备金   总储备金
        uint reservesPrior = totalReserves;
        // 之前借款指数 借款指数
        uint borrowIndexPrior = borrowIndex;

        /* Calculate the current borrow interest rate */
        // 获取借款利率
        uint borrowRateMantissa = interestRateModel.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);
        // 借款利率不能大于最大借款利率 borrowRateMaxMantissa
        require(borrowRateMantissa <= borrowRateMaxMantissa, "borrow rate is absurdly high");

        /* Calculate the number of blocks elapsed since the last accrual */
        // subUint(a,b)  if b < a no_error else error_溢出 
        // 获取当前区块 - 最新区块 = 相差几个区块
        (MathError mathErr, uint blockDelta) = subUInt(currentBlockNumber, accrualBlockNumberPrior);
        // 当前区块 要大于或者等 最近计算过利息的区块
        require(mathErr == MathError.NO_ERROR, "could not calculate block delta");

        /*
         *  Calculate the interest accumulated into borrows and reserves and the new index:
         *  计算累积到借款和储备金中的利息以及新指数：
         *  simpleInterestFactor = borrowRate * blockDelta 区块区间内的单位利息
         *  interestAccumulated = simpleInterestFactor * totalBorrows 表示总借款在该区块区间内产生的总利息
         *  totalBorrowsNew = interestAccumulated + totalBorrows 将总利息累加到总借款中
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves 根据储备金率将部分利息累加到储备金中
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex 累加借款指数
         */

        Exp memory simpleInterestFactor;
        uint interestAccumulated;   //  表示总借款在该区块区间内产生的总利息
        uint totalBorrowsNew;       //  将总利息累加到总借款中
        uint totalReservesNew;      //  根据储备金率将部分利息累加到储备金中
        uint borrowIndexNew;        //  累加借款指数

        // 两个区块间大鹅累计借款利率
        // 借款利率 * 未计算利率的区块 = 未计算利率的区块产生的利率
        (mathErr, simpleInterestFactor) = mulScalar(Exp({mantissa: borrowRateMantissa}), blockDelta);
        console.log(simpleInterestFactor.mantissa);
        //  没有错误往下继续走，错误的话进去返回。
        // failOpaque 函数是抛出错误
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_SIMPLE_INTEREST_FACTOR_CALCULATION_FAILED, uint(mathErr));
        }

        // 总借款在区块之间产生的利息总数
        // simpleInterestFactor * borrowsPrior（总借款额度）
        console.log("simpleInterestFactor, borrowsPrior", simpleInterestFactor.mantissa, borrowsPrior);
        (mathErr, interestAccumulated) = mulScalarTruncate(simpleInterestFactor, borrowsPrior);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_ACCUMULATED_INTEREST_CALCULATION_FAILED, uint(mathErr));
        }

        // 计算区块之间利息总数+总借款额度
        // 利息总数 + 总借款额度 = 借款总总数
        console.log("interestAccumulated, borrowsPrior",interestAccumulated, borrowsPrior);
        (mathErr, totalBorrowsNew) = addUInt(interestAccumulated, borrowsPrior);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_NEW_TOTAL_BORROWS_CALCULATION_FAILED, uint(mathErr));
        }

        // 计算储备金总额 总利息的一部分，算入总储备金
        // 储备金总额 = 储备因子(储备率) * 应计利息 + 当前的储备金总额。
        // reserveFactorMantissa * interestAccumulated + reservesPrior
        console.log("Exp({mantissa: reserveFactorMantissa}), interestAccumulated, reservesPrior",reserveFactorMantissa, interestAccumulated, reservesPrior);
        (mathErr, totalReservesNew) = mulScalarTruncateAddUInt(Exp({mantissa: reserveFactorMantissa}), interestAccumulated, reservesPrior);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_NEW_TOTAL_RESERVES_CALCULATION_FAILED, uint(mathErr));
        }
        
        // 累加借款指数
        // 区块之间产生的总利率 * 借款指数 + 借款指数
        // // console.log("simpleInterestFactor, borrowIndexPrior, borrowIndexPrior",simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);
        (mathErr, borrowIndexNew) = mulScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);
        if (mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.ACCRUE_INTEREST_NEW_BORROW_INDEX_CALCULATION_FAILED, uint(mathErr));
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockNumber = currentBlockNumber;    //  当前区块
        borrowIndex = borrowIndexNew;       //  借款指数
        totalBorrows = totalBorrowsNew;     //  借款总量
        totalReserves = totalReservesNew;   //  储备金总量

        /* We emit an AccrueInterest event */
        emit AccrueInterest(
            cashPrior,  //  标的资产总额度
            interestAccumulated,    //  利息 
            borrowIndexNew,     
            totalBorrowsNew
        );
        // // console.log("Error.NO_ERROR",Error.NO_ERROR);
        return uint(Error.NO_ERROR);
    }

    /**
    * @notice Sender向市场提供资产并接收cToken作为交换
    * @dev 除非还原，否则无论操作是否成功都会产生利息
    * @param mintAmount 要供应的基础资产的金额
    */
    // 指定token兑换cToken
    // * @return（uint，uint）错误代码（0=成功，否则为失败，请参阅ErrorReporter.sol）和实际的薄荷金额。
    // 供应功能允许供应商将资产转移到货币市场。然后，该资产开始根据该资产的当前供应利率累计利息。
    function mintInternal(uint mintAmount) internal nonReentrant returns (uint, uint) {
        // 计算利息
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // 在同一区块的话 不执行
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return (fail(Error(error), FailureInfo.MINT_ACCRUE_INTEREST_FAILED), 0);
        }
        // mintFresh emits the actual Mint event if successful and logs on errors, so we don't need to
        return mintFresh(msg.sender, mintAmount);
    }
    // 临时变量
    struct MintLocalVars {
        Error err;
        MathError mathErr;
        uint exchangeRateMantissa;  //  汇率
        uint mintTokens;    //  mint tolen
        uint totalSupplyNew;    //  token总数
        uint accountTokensNew;  //  用户最新token
        uint actualMintAmount;  //  实际铸造数量
    }

    /**
    * @notice 用户向市场提供资产并获得 cToken 作为交换
    * @dev 假设利息已经累积到当前区块
    * @param minter 提供资产的账户地址
    * @param mintAmount 要供应的标的资产的数量
    * @return (uint, uint) 错误代码（0=成功，否则失败，请参阅 ErrorReporter.sol）和实际铸币量。
    */
    //  计算能铸造多少代币
    function mintFresh(address minter, uint mintAmount) internal returns (uint, uint) {
        
        /* Fail if mint not allowed */
        // 检查是否允许铸币 代币是否上市
        uint allowed = comptroller.mintAllowed(address(this), minter, mintAmount);
        // 这里居然检查的不是error.noerror
        // 检查是否允许铸币和是否上市
        if (allowed != 0) {
            return (failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.MINT_COMPTROLLER_REJECTION, allowed), 0);
        }

        /* Verify market's block number equals current block number */
        // 只能在一个区块完成
        if (accrualBlockNumber != getBlockNumber()) {
            return (fail(Error.MARKET_NOT_FRESH, FailureInfo.MINT_FRESHNESS_CHECK), 0);
        }

        MintLocalVars memory vars;
        //  错误代码 存款汇率   获取存款汇率
        (vars.mathErr, vars.exchangeRateMantissa) = exchangeRateStoredInternal();
        if (vars.mathErr != MathError.NO_ERROR) {
            return (failOpaque(Error.MATH_ERROR, FailureInfo.MINT_EXCHANGE_RATE_READ_FAILED, uint(vars.mathErr)), 0);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
        *我们为minter和mintAmount调用“doTransferIn”。
        *注意：cToken必须处理ERC-20和ETH基础之间的变化。
        *“doTransferIn”会在出现任何错误时恢复，因为我们无法确定
        *出现副作用。该函数返回实际转移的金额，
        *在收费的情况下。成功后，cToken将持有额外的“actualMintMount”`
        *现金。
        */
        //  cToken 和cEth 不通方法实现
        // 当前合约调用转帐到当前合约 并且返回转移额度
        vars.actualMintAmount = doTransferIn(minter, mintAmount);
        // console.log("获取转账输入", vars.actualMintAmount);
        /*
         * 得到当前汇率并计算要铸造的cToken数量：
         *  mintTokens = actualMintAmount / exchangeRate
         */
        // mintTokens = actualMintAmount / exchangeRate
        // 这次新增的数量 / 汇率 =  这次要创建的cToken
        (vars.mathErr, vars.mintTokens) = divScalarByExpTruncate(vars.actualMintAmount, Exp({mantissa: vars.exchangeRateMantissa}));
        require(vars.mathErr == MathError.NO_ERROR, "MINT_EXCHANGE_CALCULATION_FAILED");

        /*
         * 计算新的cTokens总供应量和minter令牌余额，检查溢出：
         */
        // totalSupplyNew = totalSupply + mintTokens
        (vars.mathErr, vars.totalSupplyNew) = addUInt(totalSupply, vars.mintTokens);
        require(vars.mathErr == MathError.NO_ERROR, "MINT_NEW_TOTAL_SUPPLY_CALCULATION_FAILED");
        
        // accountTokensNew = accountTokens[minter] + mintTokens
        (vars.mathErr, vars.accountTokensNew) = addUInt(accountTokens[minter], vars.mintTokens);
        require(vars.mathErr == MathError.NO_ERROR, "MINT_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED");

        /* 将先前计算的值写入存储 */
        totalSupply = vars.totalSupplyNew;
        accountTokens[minter] = vars.accountTokensNew;

        /* We emit a Mint event, and a Transfer event */
        emit Mint(minter, vars.actualMintAmount, vars.mintTokens);
        emit Transfer(address(this), minter, vars.mintTokens);

        /* We call the defense hook */
        // unused function
        // comptroller.mintVerify(address(this), minter, vars.actualMintAmount, vars.mintTokens);
        // console.log("vars.actualMintAmount 获取铸造的数量", vars.actualMintAmount);
        return (uint(Error.NO_ERROR), vars.actualMintAmount);
    }

    /**
    * @notice Sender兑换cToken换取基础资产
    * @dev 除非还原，否则无论操作是否成功都会产生利息
    * @param redeemTokens 要兑换为基础的cTokens数量
    * @return uint 0=成功，否则为失败（有关详细信息，请参阅ErrorReporter.sol）
    */
    //  获取全部赎回数量情况下 cToken对换token得数量
    // 提款功能将用户的资产从货币市场转回给用户，具有降低协议中用户的供给平衡的作用。
    // 根据最新的汇率计算cToken能换多少标的资产
    function redeemInternal(uint redeemTokens) internal nonReentrant returns (uint) {
        // 计算汇率
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted redeem failed
            return fail(Error(error), FailureInfo.REDEEM_ACCRUE_INTEREST_FAILED);
        }
        // redeemFresh emits redeem-specific logs on errors, so we don't need to
        // 计算最新赎回数量
        return redeemFresh(msg.sender, redeemTokens, 0);
    }

    /**
    * @notice Sender兑换cToken以换取指定数量的基础资产
    * @dev 除非还原，否则无论操作是否成功都会产生利息
    * @param redeemAmount 从兑换 cTokens中获得的基础金额
    * @return uint 0=成功，否则为失败（有关详细信息，请参阅ErrorReporter.sol）
    */
    // 根据传入标的资产数量  兑换出 标的资产 发送给用户。
    function redeemUnderlyingInternal(uint redeemAmount) internal nonReentrant returns (uint) {
        // 计算汇率
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted redeem failed
            return fail(Error(error), FailureInfo.REDEEM_ACCRUE_INTEREST_FAILED);
        }
        // redeemFresh emits redeem-specific logs on errors, so we don't need to
        // 赎回标的资产
        return redeemFresh(msg.sender, 0, redeemAmount);
    }

    struct RedeemLocalVars {
        Error err;
        MathError mathErr;
        uint exchangeRateMantissa;  //  利息
        uint redeemTokens;          //  赎回数量
        uint redeemAmount;          //  赎回指定数量
        uint totalSupplyNew;        //  总量
        uint accountTokensNew;      //  
    }

    /**
    * @notice 用户兑换cToken以换取基础资产
    * @dev 假设利息已经累积到当前区块
    * @param 兑换者兑换代币的账户地址
    * @param redeemTokensIn 要兑换为基础的cTokens的数量（只有一个recemvetokensin或recemveAmountIn可能不为零）
    * @param redeemAmountIn 从兑换cTokens中接收的基础代币数量（只能有一个recovemTokensIn或recovemAmuntIn为非零）
    * @return uint 0=成功，否则为失败（有关详细信息，请参阅ErrorReporter.sol）
    */
    //  计算 赎回 cToken 兑换 token 数量
    function redeemFresh(
        address payable redeemer, //    用户地址
        uint redeemTokensIn,    //  赎回cToken数量
        uint redeemAmountIn     //  赎回标的资产数量
    ) internal returns (uint) {
        // 必须有一个情况是0
        require(redeemTokensIn == 0 || redeemAmountIn == 0, "one of redeemTokensIn or redeemAmountIn must be zero");

        RedeemLocalVars memory vars;

        /* exchangeRate = invoke Exchange Rate Stored() */
        // 获取存款汇率
        (vars.mathErr, vars.exchangeRateMantissa) = exchangeRateStoredInternal();
        if (vars.mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_EXCHANGE_RATE_READ_FAILED, uint(vars.mathErr));
        }

        /* If redeemTokensIn > 0: */
        // 赎回cToken大于 0 
        // 根据cToken算能换多少标的资产数量
        // 要么输入cToken 要么 输入标的资产 肯定只能存在一个。
        if (redeemTokensIn > 0) {
            /*
             * 计算兑换率和待赎回标的金额：
             *  redeemTokens = redeemTokensIn
             */
            vars.redeemTokens = redeemTokensIn;
            // redeemAmount = redeemTokensIn x exchangeRateCurrent

            // 标的资产数量 == 存款利率 * 全部额度
            (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(Exp({mantissa: vars.exchangeRateMantissa}), redeemTokensIn);
            // console.log("vars.redeemAmount > 0", vars.redeemAmount);
            if (vars.mathErr != MathError.NO_ERROR) {
                return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_EXCHANGE_TOKENS_CALCULATION_FAILED, uint(vars.mathErr));
            }
        }
        // 根据传入标的资产数量能换多少cToken
        else {
            /*
             * 获得当前汇率并计算要兑换的金额：
             *  redeemTokens = redeemAmountIn / exchangeRate
             *  redeemAmount = redeemAmountIn
             */
            // cToken的数量 = 标的资产数量 / 汇率
            (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(redeemAmountIn, Exp({mantissa: vars.exchangeRateMantissa}));
            if (vars.mathErr != MathError.NO_ERROR) {
                return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_EXCHANGE_AMOUNT_CALCULATION_FAILED, uint(vars.mathErr));
            }
    
            // 赎回的额度
            vars.redeemAmount = redeemAmountIn;
        }
        // console.log("vars.redeemTokens",vars.redeemTokens);
        // console.log("vars.redeemAmount 价格",vars.redeemAmount);

        /* Fail if redeem not allowed */
        // 检查账户是否允许兑换
        uint allowed = comptroller.redeemAllowed(address(this), redeemer, vars.redeemTokens);
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.REDEEM_COMPTROLLER_REJECTION, allowed);
        }

        /* 验证市场的区块数 == 当前区块数*/
        if (accrualBlockNumber != getBlockNumber()) {
            return fail(Error.MARKET_NOT_FRESH, FailureInfo.REDEEM_FRESHNESS_CHECK);
        }

        /*
         * 计算新的总供应和赎回余额，并检查下溢：
         */
        // totalSupplyNew = totalSupply - redeemTokens
        (vars.mathErr, vars.totalSupplyNew) = subUInt(totalSupply, vars.redeemTokens);
        if (vars.mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_NEW_TOTAL_SUPPLY_CALCULATION_FAILED, uint(vars.mathErr));
        }
        // accountTokensNew = accountTokens[redeemer] - redeemTokens
        (vars.mathErr, vars.accountTokensNew) = subUInt(accountTokens[redeemer], vars.redeemTokens);
        if (vars.mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.REDEEM_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED, uint(vars.mathErr));
        }

        /* Fail gracefully if protocol has insufficient cash */
        // 计算价格
        // console.log("vars.redeemAmount 价格", vars.redeemAmount);
        if (getCashPrior() < vars.redeemAmount) {
            return fail(Error.TOKEN_INSUFFICIENT_CASH, FailureInfo.REDEEM_TRANSFER_OUT_NOT_POSSIBLE);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
        *我们为赎回者和赎回金额调用doTransferOut。
        *注意：cToken必须处理ERC-20和ETH基础之间的变化。
        *成功后，cToken的兑换金额减去现金。
        *如果出现任何问题，doTransferOut将恢复，因为我们无法确定是否发生了副作用。
        */
        doTransferOut(redeemer, vars.redeemAmount);

        /* 将先前计算的值写入存储 */
        totalSupply = vars.totalSupplyNew;
        accountTokens[redeemer] = vars.accountTokensNew;

        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(redeemer, address(this), vars.redeemTokens);
        emit Redeem(redeemer, vars.redeemAmount, vars.redeemTokens);

        /* We call the defense hook */
        // 检查两个是否为0
        comptroller.redeemVerify(address(this), redeemer, vars.redeemAmount, vars.redeemTokens);

        return uint(Error.NO_ERROR);
    }

    /**
    * @notice 发送方从协议中借用资产到自己的地址
    * @param borrowAmount 要借入的基础资产的金额
    * @return uint 0=成功，否则为失败（有关详细信息，请参阅ErrorReporter.sol）
    */
    // 借钱 需要先有存款额度
    // 借款功能将资产从货币市场转移到使用者手中，其作用是根据借入资产的当前借款利率开始利息累积。
    function borrowInternal(uint borrowAmount) internal nonReentrant returns (uint) {
        //  计算 借款利率
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return fail(Error(error), FailureInfo.BORROW_ACCRUE_INTEREST_FAILED);
        }
        // borrowFresh emits borrow-specific logs on errors, so we don't need to
        // 借钱 到自己账户中
        return borrowFresh(msg.sender, borrowAmount);
    }

    struct BorrowLocalVars {
        MathError mathErr;
        uint accountBorrows;    //  借钱账户
        uint accountBorrowsNew; //  借款账户 新
        uint totalBorrowsNew;   //  最新借款总量
    }

    /**
    * @notice 用户从协议中借用资产到自己的地址
    * @param borrowAmount 要借入的基础资产的金额
    * @return uint 0=成功，否则为失败（有关详细信息，请参阅ErrorReporter.sol）
    */
    //  借款 接到之间账户地址中
    function borrowFresh(
        address payable borrower,   //  借钱地址
        uint borrowAmount       //  借钱数量
    ) internal returns (uint) {
        console.log("borrowFresh");
        /* Fail if borrow not allowed */
        // 检查用户是否允许借款
        uint allowed = comptroller.borrowAllowed(address(this), borrower, borrowAmount);
        console.log("111",allowed);
        // console.log("allowed", allowed);
        // 流动性不足
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.BORROW_COMPTROLLER_REJECTION, allowed);
        }

        /* 只能在同一个区块执行 */
        if (accrualBlockNumber != getBlockNumber()) {
            return fail(Error.MARKET_NOT_FRESH, FailureInfo.BORROW_FRESHNESS_CHECK);
        }

        /* Fail gracefully if protocol has insufficient underlying cash */
        // console.log("getCashPrior() < borrowAmount", getCashPrior() < borrowAmount);
        if (getCashPrior() < borrowAmount) {
            // 令牌现金不足
            return fail(Error.TOKEN_INSUFFICIENT_CASH, FailureInfo.BORROW_CASH_NOT_AVAILABLE);
        }

        BorrowLocalVars memory vars;

        /*
         *  计算新的借款人和总借款余额，溢出失败：
         */
        // 获取借款人额度
        (vars.mathErr, vars.accountBorrows) = borrowBalanceStoredInternal(borrower);
        if (vars.mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.BORROW_ACCUMULATED_BALANCE_CALCULATION_FAILED, uint(vars.mathErr));
        }
        // accountBorrowsNew = accountBorrows + borrowAmount
        // 用户借款额度 = 用户借款额度 + 借款基础额度
        (vars.mathErr, vars.accountBorrowsNew) = addUInt(vars.accountBorrows, borrowAmount);
        // console.log("vars.accountBorrows",vars.accountBorrows);
        // console.log("borrowAmount",borrowAmount);
        // console.log("vars.accountBorrowsNew",vars.accountBorrowsNew);
        if (vars.mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED, uint(vars.mathErr));
        }
        // totalBorrowsNew = totalBorrows + borrowAmount
        // 最新借款总额度 = 之前借款额度 + 基础基础金额
        (vars.mathErr, vars.totalBorrowsNew) = addUInt(totalBorrows, borrowAmount);
        if (vars.mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED, uint(vars.mathErr));
        }
        // console.log("vars.totalBorrowsNew", vars.totalBorrowsNew);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
          * 我们为借用者和借用金额调用 doTransferOut。
          * 注意：cToken 必须处理 ERC-20 和 ETH 底层之间的变化。
          * 成功时，cToken 借入的现金金额减少。
          * 如果出现任何问题，doTransferOut 会恢复，因为我们无法确定是否发生了副作用。
          */
        doTransferOut(borrower, borrowAmount);

        /* 将之前计算的值写入存储 */
        accountBorrows[borrower].principal = vars.accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = vars.totalBorrowsNew;
        console.log(
            "借钱",
            accountBorrows[borrower].principal,
            accountBorrows[borrower].interestIndex, 
            totalBorrows
        );
        // console.log("accountBorrows[borrower].principal", accountBorrows[borrower].principal);
        // console.log("accountBorrows[borrower].interestIndex", accountBorrows[borrower].interestIndex);
        // console.log("totalBorrows", totalBorrows);
        /* We emit a Borrow event */
        emit Borrow(borrower, borrowAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);

        /* We call the defense hook */
        // unused function
        // comptroller.borrowVerify(address(this), borrower, borrowAmount);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice 发起人偿还自己的借款
      * @param repayAmount 还款金额
      * @return (uint, uint) 错误码（0=成功，否则失败，见ErrorReporter.sol），实际还款金额。
      */
    //  还款 自己还自己的钱
    // 偿还借款功能将借入的资产转入货币市场，具有减少使用者借款余额的作用。
    function repayBorrowInternal(uint repayAmount) internal nonReentrant returns (uint, uint) {
        // 计算利息
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return (fail(Error(error), FailureInfo.REPAY_BORROW_ACCRUE_INTEREST_FAILED), 0);
        }
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        // 自己还自己的钱   
        return repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    /**
      * @notice 发起人偿还属于借款人的借款
      * @param borrower 还清债务的账户
      * @param repayAmount 还款金额
      * @return (uint, uint) 错误码（0=成功，否则失败，见ErrorReporter.sol），实际还款金额。
      */
    //  还款 我帮别人还款，可以全部还或者还一部分
    function repayBorrowBehalfInternal(address borrower, uint repayAmount) internal nonReentrant returns (uint, uint) {
        // 计算利息
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted borrow failed
            return (fail(Error(error), FailureInfo.REPAY_BEHALF_ACCRUE_INTEREST_FAILED), 0);
        }
        // repayBorrowFresh emits repay-borrow-specific logs on errors, so we don't need to
        // 帮指定账户还钱
        return repayBorrowFresh(msg.sender, borrower, repayAmount);
    }

    struct RepayBorrowLocalVars {
        Error err;
        MathError mathErr;
        uint repayAmount;   //  还款金额
        uint borrowerIndex; //  借款人的指数
        uint accountBorrows;    //  借款账户
        uint accountBorrowsNew; //  借款账户新
        uint totalBorrowsNew;   //  新借款总量
        uint actualRepayAmount; //  实际还款额度
    }

    /**
      * @notice 借款由另一个用户（可能是借款人）偿还。
      * @param payer 还清借款的账户
      * @param borrower 还清债务的账户
      * @param repayAmount 退还的代币数量
      * @return (uint, uint) 错误码（0=成功，否则失败，见ErrorReporter.sol），实际还款金额。
      */
    // 还款函数
    function repayBorrowFresh(
        address payer, // 还款人
        address borrower,   //  给谁还
        uint repayAmount    //  额度
    ) internal returns (uint, uint) {
        /* Fail if repayBorrow not allowed */
        // 检查账户是否允许还款。 只检查了是否上市
        uint allowed = comptroller.repayBorrowAllowed(address(this), payer, borrower, repayAmount);
        if (allowed != 0) {
            return (failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.REPAY_BORROW_COMPTROLLER_REJECTION, allowed), 0);
        }

        /* 只能在同一个区块中执行 */
        if (accrualBlockNumber != getBlockNumber()) {
            return (fail(Error.MARKET_NOT_FRESH, FailureInfo.REPAY_BORROW_FRESHNESS_CHECK), 0);
        }

        RepayBorrowLocalVars memory vars;

        /* We remember the original borrowerIndex for verification purposes */
        // 获取借款人借款时候的 指数
        vars.borrowerIndex = accountBorrows[borrower].interestIndex;

        /* We fetch the amount the borrower owes, with accumulated interest */
        // 获取借款额度
        (vars.mathErr, vars.accountBorrows) = borrowBalanceStoredInternal(borrower);
        if (vars.mathErr != MathError.NO_ERROR) {
            return (failOpaque(Error.MATH_ERROR, FailureInfo.REPAY_BORROW_ACCUMULATED_BALANCE_CALCULATION_FAILED, uint(vars.mathErr)), 0);
        }

        /* If repayAmount == -1, repayAmount = accountBorrows */
        // 退还代币
        if (repayAmount == uint(-1)) {
            // 把全部借款额度还清
            vars.repayAmount = vars.accountBorrows;
        } else {
            // 按照传入的 还款
            vars.repayAmount = repayAmount;
        }
        console.log("vars.repayAmount  ", vars.repayAmount );
        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
          * 我们为付款人和repayAmount 调用doTransferIn
          * 注意：cToken 必须处理 ERC-20 和 ETH 底层之间的变化。
          * 成功时，cToken 持有额外的 repayAmount 现金。
          * 如果出现任何问题，doTransferIn 会恢复，因为我们无法确定是否发生了副作用。
          * 在收费的情况下，它会返回实际转账的金额。
          */
        //  转移token方法 cErc20 和cEth中自己实现
        // 获取借款额度
        vars.actualRepayAmount = doTransferIn(payer, vars.repayAmount);

        /*
          * 计算新的借款人和总借款余额，在下溢失败时：
          */
  
        // 账户借款新 = 账户借款 - 实际还款额
        //  accountBorrowsNew = accountBorrows - actualRepayAmount
        (vars.mathErr, vars.accountBorrowsNew) = subUInt(vars.accountBorrows, vars.actualRepayAmount);
        require(vars.mathErr == MathError.NO_ERROR, "REPAY_BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED");// 还款_借款_新账户_借款_余额_计算失败

        // 总借款新 = 总借款 - 实际还款额
        // totalBorrowsNew = totalBorrows - actualRepayAmount
        (vars.mathErr, vars.totalBorrowsNew) = subUInt(totalBorrows, vars.actualRepayAmount);
        require(vars.mathErr == MathError.NO_ERROR, "REPAY_BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED");

        /* 更新借款额度 记录到数据中 */
        accountBorrows[borrower].principal = vars.accountBorrowsNew;    //  借款额度
        accountBorrows[borrower].interestIndex = borrowIndex;           //  借款指标
        totalBorrows = vars.totalBorrowsNew;    //  借款总量
        console.log("jiekuang",accountBorrows[borrower].principal, accountBorrows[borrower].interestIndex,totalBorrows);
        /* We emit a RepayBorrow event */
        emit RepayBorrow(payer, borrower, vars.actualRepayAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);

        /* We call the defense hook */
        // unused function
        // comptroller.repayBorrowVerify(address(this), payer, borrower, vars.actualRepayAmount, vars.borrowerIndex);
        // console.log("vars.actualRepayAmount 还款额度 ", vars.actualRepayAmount);
        return (uint(Error.NO_ERROR), vars.actualRepayAmount);
    }

    /**
      * @notice 发件人清算借款人的抵押品。
      * 被扣押的抵押品被转移给清算人。
      * @param borrower 该cToken的要被清算的借款人
      * @param cTokenCollateral 从借款人那里获取抵押品的市场
      * @param repayAmount 要偿还的标的借入资产的金额
      * @return (uint, uint) 错误码（0=成功，否则失败，见ErrorReporter.sol），实际还款金额。
      */
    // 清算
    // 如果用户的总资产/未偿还的借贷支持 < 抵押率  就会触发清算
    // 如果发生清算，则清算人可以代表被清算的个人（也称为清算人）偿还部分或全部未偿还的借款。
    //  清算人最多只能清算借款人额度的50%
    function liquidateBorrowInternal(
        address borrower,   //  帮哪个用户还钱
        uint repayAmount,   //  还多少钱
        CTokenInterface cTokenCollateral    //  用什么抵押品资产
    ) internal nonReentrant returns (uint, uint) {
        // 计算借款利率
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted liquidation failed
            return (fail(Error(error), FailureInfo.LIQUIDATE_ACCRUE_BORROW_INTEREST_FAILED), 0);
        }
        
        // 获取抵押品的借款利率
        error = cTokenCollateral.accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but we still want to log the fact that an attempted liquidation failed
            return (fail(Error(error), FailureInfo.LIQUIDATE_ACCRUE_COLLATERAL_INTEREST_FAILED), 0);
        }

        // liquidateBorrowFresh emits borrow-specific logs on errors, so we don't need to
        return liquidateBorrowFresh(msg.sender, borrower, repayAmount, cTokenCollateral);
    }

    /**
      * @notice 清算人清算借款人的抵押品。
      * 被扣押的抵押品被转移给清算人。
      * @param liquidator 为你清算人还款人地址 或 扣押.抵押品的地址 == 本次还款人/还款抵押品？
      * @param borrower 该cToken的要被清算的借款人
      * @param repayAmount 要偿还的标的借入资产的金额
      * @param cTokenCollateral 从借款人那里获取抵押品的市场
      * @return (uint, uint) 错误码（0=成功，否则失败，见ErrorReporter.sol），实际还款金额。
      */
    //  指定 a 清算 b 指定额度。最多50%
    function liquidateBorrowFresh(
        address liquidator, 
        address borrower, 
        uint repayAmount, 
        CTokenInterface cTokenCollateral
    ) internal returns (uint, uint) {
        /* Fail if liquidate not allowed */
        // 检查是否允许清算
        uint allowed = comptroller.liquidateBorrowAllowed(address(this), address(cTokenCollateral), liquidator, borrower, repayAmount);
        if (allowed != 0) {
            return (failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.LIQUIDATE_COMPTROLLER_REJECTION, allowed), 0);
        }

        /* Verify market's block number equals current block number */
        if (accrualBlockNumber != getBlockNumber()) {
            return (fail(Error.MARKET_NOT_FRESH, FailureInfo.LIQUIDATE_FRESHNESS_CHECK), 0);
        }

        /* Verify cTokenCollateral market's block number equals current block number */
        // 抵押品计算过利息的区块 必须是最新区块
        if (cTokenCollateral.accrualBlockNumber() != getBlockNumber()) {
            return (fail(Error.MARKET_NOT_FRESH, FailureInfo.LIQUIDATE_COLLATERAL_FRESHNESS_CHECK), 0);
        }

        /* Fail if borrower = liquidator */
        // 借款任何清算人不能是同一个人
        if (borrower == liquidator) {
            return (fail(Error.INVALID_ACCOUNT_PAIR, FailureInfo.LIQUIDATE_LIQUIDATOR_IS_BORROWER), 0);
        }

        /* Fail if repayAmount = 0 */
        // 清算额度不能是 0
        console.log("清算额度",repayAmount);
        if (repayAmount == 0) {
            return (fail(Error.INVALID_CLOSE_AMOUNT_REQUESTED, FailureInfo.LIQUIDATE_CLOSE_AMOUNT_IS_ZERO), 0);
        }

        /* Fail if repayAmount = -1 */
        // 清算额度不能是最大额度
        if (repayAmount == uint(-1)) {
            return (fail(Error.INVALID_CLOSE_AMOUNT_REQUESTED, FailureInfo.LIQUIDATE_CLOSE_AMOUNT_IS_UINT_MAX), 0);
        }


        /* Fail if repayBorrow fails */
        // 给指定地址还款
        (uint repayBorrowError, uint actualRepayAmount) = repayBorrowFresh(
            liquidator, //  清算人
            borrower,   //  借款人
            repayAmount //  清算额度
        );
        if (repayBorrowError != uint(Error.NO_ERROR)) {
            return (fail(Error(repayBorrowError), FailureInfo.LIQUIDATE_REPAY_BORROW_FRESH_FAILED), 0);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* 计算将被扣押的抵押代币数量 */
        // 计算输入的金额 能兑换的抵押品数量 获取清算资产数量
        (uint amountSeizeError, uint seizeTokens) = comptroller.liquidateCalculateSeizeTokens(address(this), address(cTokenCollateral), actualRepayAmount);
        require(amountSeizeError == uint(Error.NO_ERROR), "LIQUIDATE_COMPTROLLER_CALCULATE_AMOUNT_SEIZE_FAILED");

        /* Revert if borrower collateral token balance < seizeTokens */
        // 检测 借款人代币数量  >= 清算的数量
        require(cTokenCollateral.balanceOf(borrower) >= seizeTokens, "LIQUIDATE_SEIZE_TOO_MUCH");

        // If this is also the collateral, run seizeInternal to avoid re-entrancy, otherwise make an external call
        // 如果这也是抵押品，请运行seizeInternal 以避免重新进入，否则进行外部调用
        uint seizeError;
        // 如果是自己调用
        // 抵押品是当前市场合约调用 ？？？
        // console.log("address(cTokenCollateral) == address(this)", address(cTokenCollateral), address(this));
        if (address(cTokenCollateral) == address(this)) {
            // 调用抵押品 => 
            seizeError = seizeInternal(
                address(this), 
                liquidator, 
                borrower, 
                seizeTokens
            );
        } else {
            // 抵押代币转移给清算人
            seizeError = cTokenCollateral.seize(liquidator, borrower, seizeTokens);
        }

        /* Revert if seize tokens fails (since we cannot be sure of side effects) */
        require(seizeError == uint(Error.NO_ERROR), "token seizure failed");

        /* We emit a LiquidateBorrow event */
        emit LiquidateBorrow(liquidator, borrower, actualRepayAmount, address(cTokenCollateral), seizeTokens);

        /* We call the defense hook */
        // unused function
        // comptroller.liquidateBorrowVerify(address(this), address(cTokenCollateral), liquidator, borrower, actualRepayAmount, seizeTokens);

        return (uint(Error.NO_ERROR), actualRepayAmount);
    }

    /**
      * @notice 将抵押代币（这个市场）转移给清算人。
      * @dev 将失败，除非在清算过程中被另一个 cToken 调用。
      * 使用 msg.sender 作为借用的 cToken 而不是参数绝对至关重要。
      * @param liquidator 接收被扣押抵押品的账户
      * @param borrower 被扣押的账户
      * @param seizeTokens 要获取的 cToken 数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    function seize(address liquidator, address borrower, uint seizeTokens) external nonReentrant returns (uint) {
        return seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
    }

    struct SeizeInternalLocalVars {
        MathError mathErr;
        uint borrowerTokensNew;
        uint liquidatorTokensNew;
        uint liquidatorSeizeTokens;
        uint protocolSeizeTokens;
        uint protocolSeizeAmount;
        uint exchangeRateMantissa;
        uint totalReservesNew;
        uint totalSupplyNew;
    }

    /**
      * @notice 将抵押代币（这个市场）转移给清算人。
      * @dev 仅在实物清算期间调用，或在另一个 CToken 清算期间由liquidateBorrow 调用。
      * 使用 msg.sender 作为抓取器 cToken 而不是参数绝对至关重要。
      * @param seizerToken 扣押抵押品的合约（即借来的 cToken）
      * @param liquidator 接收被扣押抵押品的账户
      * @param borrower 被扣押的账户
      * @param seizeTokens 要获取的 cToken 数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    function seizeInternal(
        address seizerToken,
        address liquidator, //  扣押清算账户
        address borrower,   //  
        uint seizeTokens
    ) internal returns (uint) {
        /* Fail if seize not allowed */
        // 检测是否允许扣押 
        uint allowed = comptroller.seizeAllowed(address(this), seizerToken, liquidator, borrower, seizeTokens);
        if (allowed != 0) {
            return failOpaque(Error.COMPTROLLER_REJECTION, FailureInfo.LIQUIDATE_SEIZE_COMPTROLLER_REJECTION, allowed);
        }

        /* Fail if borrower = liquidator */
        // 被扣押抵押品地址 != 被扣押账户
        if (borrower == liquidator) {
            return fail(Error.INVALID_ACCOUNT_PAIR, FailureInfo.LIQUIDATE_SEIZE_LIQUIDATOR_IS_BORROWER);
        }

        SeizeInternalLocalVars memory vars;

        /*
          * 计算新的借款人和清算人代币余额，下溢/溢出失败：
          */

        // borrowerTokensNew = accountTokens[被扣押账户] - seizeTokens
        (vars.mathErr, vars.borrowerTokensNew) = subUInt(accountTokens[borrower], seizeTokens);
        if (vars.mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.LIQUIDATE_SEIZE_BALANCE_DECREMENT_FAILED, uint(vars.mathErr));
        }

        // 更具要获取cToken的数量 * 从清算人中获取的清算激励？？？
        vars.protocolSeizeTokens = mul_(seizeTokens, Exp({mantissa: protocolSeizeShareMantissa}));
        // 此次清算激励？？的总数 =  seizeTokens - vars.protocolSeizeTokens
        vars.liquidatorSeizeTokens = sub_(seizeTokens, vars.protocolSeizeTokens);

        // 获取存款汇率
        (vars.mathErr, vars.exchangeRateMantissa) = exchangeRateStoredInternal();
        require(vars.mathErr == MathError.NO_ERROR, "exchange rate math error");
        // 扣押总量  = 存款汇率 * cToken总额(获取cToken的总量+清算激励)
        vars.protocolSeizeAmount = mul_ScalarTruncate(Exp({mantissa: vars.exchangeRateMantissa}), vars.protocolSeizeTokens);

        // 新储备总额 = 资产总额 + 扣押总量
        vars.totalReservesNew = add_(totalReserves, vars.protocolSeizeAmount);
        //  新资产总额 = 资产总额 - 扣押总数
        vars.totalSupplyNew = sub_(totalSupply, vars.protocolSeizeTokens);
        
        //  liquidatorTokensNew(新清算人总数) = accountTokens[清算人] + 清算额度
        (vars.mathErr, vars.liquidatorTokensNew) = addUInt(accountTokens[liquidator], vars.liquidatorSeizeTokens);
        if (vars.mathErr != MathError.NO_ERROR) {
            return failOpaque(Error.MATH_ERROR, FailureInfo.LIQUIDATE_SEIZE_BALANCE_INCREMENT_FAILED, uint(vars.mathErr));
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        //  储备总额
        totalReserves = vars.totalReservesNew;
        // 更新流通代币总量总量
        totalSupply = vars.totalSupplyNew;
        // 更新 代清算人和清算和的资产总量
        // 这里 清算人手机代币数量没有减少，减少的是系统中有的数量。当清算人提出超出系统的清算数量不会提取成功，因为系统额度不足。
        accountTokens[borrower] = vars.borrowerTokensNew;
        accountTokens[liquidator] = vars.liquidatorTokensNew;

        /* Emit a Transfer event */
        emit Transfer(borrower, liquidator, vars.liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), vars.protocolSeizeTokens);
        emit ReservesAdded(address(this), vars.protocolSeizeAmount, vars.totalReservesNew);

        /* We call the defense hook */
        // unused function
        // comptroller.seizeVerify(address(this), seizerToken, liquidator, borrower, seizeTokens);

        return uint(Error.NO_ERROR);
    }


    /*** Admin Functions ***/

    /**
       * @notice 开始转移管理员权限。 newPendingAdmin 必须调用 `_acceptAdmin` 来完成传输。
       * @dev 管理员功能开始更改管理员。 newPendingAdmin 必须调用 `_acceptAdmin` 来完成传输。
       * @param newPendingAdmin 新的待处理管理员。
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    function _setPendingAdmin(address payable newPendingAdmin) external returns (uint) {
        // Check caller = admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PENDING_ADMIN_OWNER_CHECK);
        }

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
       * @notice 接受管理员权限的转移。 msg.sender 必须是 pendingAdmin
       * @dev 管理员功能，用于待定管理员接受角色并更新管理员
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    function _acceptAdmin() external returns (uint) {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
        // 接受权限着不能是之前的管理员和黑洞地址
        if (msg.sender != pendingAdmin || msg.sender == address(0)) {
            return fail(Error.UNAUTHORIZED, FailureInfo.ACCEPT_ADMIN_PENDING_ADMIN_CHECK);
        }

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice 为市场设置新的审计员
      * @dev 管理员功能设置一个新的审计员
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    function _setComptroller(ComptrollerInterface newComptroller) public returns (uint) {
        // Check caller is admin
        // 只能是admin 才能设置
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COMPTROLLER_OWNER_CHECK);
        }
        // console.log("comptroller", address(comptroller));
        ComptrollerInterface oldComptroller = comptroller;
        // 确保调用 comptroller.isComptroller() 返回 true
        // 确保comptroller 合约
        // console.log("newComptroller.isComptroller()", newComptroller.isComptroller());
        require(newComptroller.isComptroller(), "marker method returned false");

        // Set market's comptroller to newComptroller
        // 修改控制器 为新的控制器。
        comptroller = newComptroller;

        // Emit NewComptroller(oldComptroller, newComptroller)
        emit NewComptroller(oldComptroller, newComptroller);
    
        return uint(Error.NO_ERROR);
    }

    /**
       * @notice 产生利息并使用 _setReserveFactorFresh 为协议设置一个新的储备因子
       * @dev 管理函数来产生利息并设置一个新的储备因子
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    //  设置储备金系数
    function _setReserveFactor(uint newReserveFactorMantissa) external nonReentrant returns (uint) {
        // 计算累积利率
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted reserve factor change failed.
            return fail(Error(error), FailureInfo.SET_RESERVE_FACTOR_ACCRUE_INTEREST_FAILED);
        }
        // _setReserveFactorFresh emits reserve-factor-specific logs on errors, so we don't need to.
        return _setReserveFactorFresh(newReserveFactorMantissa);
    }

    /**
       * @notice 为协议设置新的储备因子（*需要新的应计利息）
       * @dev 管理函数设置一个新的储备因子
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    //   设置利率
    function _setReserveFactorFresh(uint newReserveFactorMantissa) internal returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_RESERVE_FACTOR_ADMIN_CHECK);
        }

        // Verify market's block number equals current block number
        //  只能在一个区块完成
        if (accrualBlockNumber != getBlockNumber()) {
            return fail(Error.MARKET_NOT_FRESH, FailureInfo.SET_RESERVE_FACTOR_FRESH_CHECK);
        }

        // Check newReserveFactor ≤ maxReserveFactor
        // 新利率要大于储备利率
        if (newReserveFactorMantissa > reserveFactorMaxMantissa) {
            return fail(Error.BAD_INPUT, FailureInfo.SET_RESERVE_FACTOR_BOUNDS_CHECK);
        }
        // 修改利率
        uint oldReserveFactorMantissa = reserveFactorMantissa;
        reserveFactorMantissa = newReserveFactorMantissa;

        emit NewReserveFactor(oldReserveFactorMantissa, newReserveFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice 通过从 msg.sender 转移产生利息并减少准备金
      * @param addAmount 增加储备的数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    //  admin 增加储备金
    function _addReservesInternal(uint addAmount) internal nonReentrant returns (uint) {
        // 计算累积利率
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted reduce reserves failed.
            return fail(Error(error), FailureInfo.ADD_RESERVES_ACCRUE_INTEREST_FAILED);
        }

        // _addReservesFresh emits reserve-addition-specific logs on errors, so we don't need to.
        (error, ) = _addReservesFresh(addAmount);
        return error;
    }

    /**
      * @notice 通过从调用者转移添加储备
      * @dev 需要新的应计利息
      * @param addAmount 增加储备的数量
      * @return (uint, uint) 错误代码（0=成功，否则失败（详见ErrorReporter.sol））和实际添加的金额，净代币费用
      */
    // 添加指定额度到 储备金总 计算出新的总储备金 并且更新
    function _addReservesFresh(uint addAmount) internal returns (uint, uint) {
        // totalReserves + actualAddAmount
        uint totalReservesNew;
        uint actualAddAmount;

        // We fail gracefully unless market's block number equals current block number
        if (accrualBlockNumber != getBlockNumber()) {
            return (fail(Error.MARKET_NOT_FRESH, FailureInfo.ADD_RESERVES_FRESH_CHECK), actualAddAmount);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
          * 我们为调用者和 addAmount 调用 doTransferIn
          * 注意：cToken 必须处理 ERC-20 和 ETH 底层之间的变化。
          * 成功时，cToken 持有额外的 addAmount 现金。
          * 如果出现任何问题，doTransferIn 会恢复，因为我们无法确定是否发生了副作用。
          * 在收费的情况下，它会返回实际转账的金额。
          */

        actualAddAmount = doTransferIn(msg.sender, addAmount);
        // 总储备金新 = 总储备金 + 实际添加金额
        totalReservesNew = totalReserves + actualAddAmount;

        /* Revert on overflow */
        require(totalReservesNew >= totalReserves, "add reserves unexpected overflow");

        // Store reserves[n+1] = reserves[n] + actualAddAmount
        // 修改总储备金额度
        totalReserves = totalReservesNew;

        /* Emit NewReserves(admin, actualAddAmount, reserves[n+1]) */
        emit ReservesAdded(msg.sender, actualAddAmount, totalReservesNew);

        /* Return (NO_ERROR, actualAddAmount) */
        return (uint(Error.NO_ERROR), actualAddAmount);
    }


    /**
      * @notice 通过转移到管理员来产生利息并减少准备金
      * @param reduceAmount 减少到准备金的数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    //  admin 减少储备金额度
    function _reduceReserves(uint reduceAmount) external nonReentrant returns (uint) {
        // 计算累积利率
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted reduce reserves failed.
            return fail(Error(error), FailureInfo.REDUCE_RESERVES_ACCRUE_INTEREST_FAILED);
        }
        // _reduceReservesFresh emits reserve-reduction-specific logs on errors, so we don't need to.
        return _reduceReservesFresh(reduceAmount);
    }

    /**
      * @notice 通过转移到管理员来减少储备
      * @dev 需要新的应计利息
      * @param reduceAmount 减少到准备金的数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    function _reduceReservesFresh(uint reduceAmount) internal returns (uint) {
        // totalReserves - reduceAmount
        uint totalReservesNew;  //  总储备金新

        // Check caller is admin
        // admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.REDUCE_RESERVES_ADMIN_CHECK);
        }

        // We fail gracefully unless market's block number equals current block number
        if (accrualBlockNumber != getBlockNumber()) {
            return fail(Error.MARKET_NOT_FRESH, FailureInfo.REDUCE_RESERVES_FRESH_CHECK);
        }

        //  如果协议没有足够的基础现金，则失败
        // console.log("getCashPrior()", getCashPrior());
        // console.log("reduceAmount", reduceAmount);
        if (getCashPrior() < reduceAmount) {
            return fail(Error.TOKEN_INSUFFICIENT_CASH, FailureInfo.REDUCE_RESERVES_CASH_NOT_AVAILABLE);
        }

        // Check reduceAmount ≤ reserves[n] (totalReserves)
        // console.log("reduceAmount > totalReserves",reduceAmount, totalReserves);
        if (reduceAmount > totalReserves) {
            return fail(Error.BAD_INPUT, FailureInfo.REDUCE_RESERVES_VALIDATION);
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)
        // 新总储备金 = 储备金 - 减少额度
        totalReservesNew = totalReserves - reduceAmount;
        // We checked reduceAmount <= totalReserves above, so this should never revert.
        require(totalReservesNew <= totalReserves, "reduce reserves unexpected underflow");

        // Store reserves[n+1] = reserves[n] - reduceAmount
        totalReserves = totalReservesNew;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(admin, reduceAmount);

        emit ReservesReduced(admin, reduceAmount, totalReservesNew);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice 产生利息并使用 _setInterestRateModelFresh 更新利率模型
      * @dev 管理功能来产生利息和更新利率模型
      * @param newInterestRateModel 要使用的新利率模型
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    //  设置利率模型
    function _setInterestRateModel(InterestRateModel newInterestRateModel) public returns (uint) {
        // 获取累积利率
        uint error = accrueInterest();
        if (error != uint(Error.NO_ERROR)) {
            // accrueInterest emits logs on errors, but on top of that we want to log the fact that an attempted change of interest rate model failed
            return fail(Error(error), FailureInfo.SET_INTEREST_RATE_MODEL_ACCRUE_INTEREST_FAILED);
        }
        // _setInterestRateModelFresh emits interest-rate-model-update-specific logs on errors, so we don't need to.
        return _setInterestRateModelFresh(newInterestRateModel);
    }

    /**
    * @notice 设置 更新 利率模型（*需要新的应计利息）
    * @dev 管理函数更新利率模型
    * @param newInterestRateModel 要使用的新利率模型
    * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
    */
    function _setInterestRateModelFresh(InterestRateModel newInterestRateModel) internal returns (uint) {

        //  用于存储旧模型以在成功时发出的事件中使用
        // // console.log("oldInterestRateModel", oldInterestRateModel);
        InterestRateModel oldInterestRateModel;

        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_INTEREST_RATE_MODEL_OWNER_CHECK);
        }

        // 创建市场时候的区块数等于当前的区块数，否则我们会失败
        if (accrualBlockNumber != getBlockNumber()) {
            return fail(Error.MARKET_NOT_FRESH, FailureInfo.SET_INTEREST_RATE_MODEL_FRESH_CHECK);
        }

        // 跟踪市场当前的利率模型
        oldInterestRateModel = interestRateModel;

        // Ensure invoke newInterestRateModel.isInterestRateModel() returns true
        // 取保调用的是利率模型区块
        require(newInterestRateModel.isInterestRateModel(), "marker method returned false");

        // Set the interest rate model to newInterestRateModel
        // 设置新的利率模型
        interestRateModel = newInterestRateModel;

        // Emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel)
        emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel);

        return uint(Error.NO_ERROR);
    }

    /*** Safe Token ***/

    /**
      * @notice 获取该合约在底层证券方面的余额
      * @dev 这不包括当前消息的值，如果有的话
      */
    //   * @return 该合约拥有的底层证券数量
    // 标的资产代币数量
    function getCashPrior() internal view returns (uint);

    /**
      * @dev 执行传输，失败时恢复。 在收费的情况下返回实际转移到协议的金额。
      * 这可能会因余额不足或津贴不足而恢复。
      */
    function doTransferIn(address from, uint amount) internal returns (uint);

    /**
      * @dev 执行转出，理想情况下在失败时返回解释性错误代码而不是恢复。
      * 如果调用者没有调用检查协议的余额，可能会由于合约中持有的现金不足而恢复。
      * 如果调用者检查了协议的余额，并验证它 >= 金额，这在正常情况下不应恢复。
      */
    function doTransferOut(address payable to, uint amount) internal;


    /*** Reentrancy Guard ***/

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    // 防止重入攻击
    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }
}

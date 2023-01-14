pragma solidity ^0.5.16;

import "./CTokenInterfaces.sol";
import "hardhat/console.sol";
/**
  * @title Compound 的 CErc20Delegator 合约
  * @notice CTokens 封装了 EIP-20 底层并委托给实现
  * @author 复合
  */
// erc20 和 ctoken交互使用 CErc20Delegator
contract CErc20Delegator is CTokenInterface, CErc20Interface, CDelegatorInterface {
    /**
    * @notice 构建一个新的货币市场
    * @param underlying_ 标的资产地址 usdt
    * @param comptroller_ 主计长地址 comptroller
    * @param interestRateModel_ 利率模型的地址
    * @param initialExchangeRateMantissa_ 初始汇率，按 1e18 缩放
    * @param name_ 此令牌的 ERC-20 名称
    * @param symbol_ 此代币的 ERC-20 符号
    * @param decimals_ 此令牌的 ERC-20 十进制精度
    * @param admin_ Address of the administrator of this token
    * @param implementation_ 合同委托实施的地址
    * @param becomeImplementationData The encoded args for becomeImplementation
    */
    // comptroller 和 interestRateModel 是可以更换的，当两者存在升级版本时，就可以分别调用 _setComptroller(newComptroller) 和 _setInterestRateModel(newInterestRateModel) 更换为升级后的合约
    constructor(
        address underlying_,    //  标的合约，每中ctoken都对应标的资产
        ComptrollerInterface comptroller_,  //  审计合约
        InterestRateModel interestRateModel_,   //  利率模型合约
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address payable admin_,
        address implementation_,
        bytes memory becomeImplementationData
    ) public {
        // Creator of the contract is admin during initialization
        admin = msg.sender;

        // First delegate gets to initialize the delegator (i.e. storage contract)
        // 委托合约调用初始化方法
        delegateTo(
            implementation_, 
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,string,string,uint8)",
                underlying_,
                comptroller_,
                interestRateModel_,
                initialExchangeRateMantissa_,
                name_,
                symbol_,
                decimals_
            )
        );

        // New implementations always get set via the settor (post-initialize)
        // 设置委托调用合约的执行地址
        _setImplementation(implementation_, false, becomeImplementationData);

        // Set the proper admin now that initialization is done
        admin = admin_;
    }

    /**
      * @notice 由管理员调用以更新委托人的实现
      * @param implementation_ 委托的新实现地址
      * @param allowResign Flag 指示是否在旧实现上调用 _resignImplementation
      * @param becomeImplementationData 要传递给 _becomeImplementation 的编码字节数据
      */
    //  设置委托调用合约的地址
    function _setImplementation(
        address implementation_, 
        bool allowResign, 
        bytes memory becomeImplementationData
    ) public {
        require(msg.sender == admin, "CErc20Delegator::_setImplementation: Caller must be admin");

        if (allowResign) {
            delegateToImplementation(abi.encodeWithSignature("_resignImplementation()"));
        }

        address oldImplementation = implementation;
        implementation = implementation_;

        delegateToImplementation(abi.encodeWithSignature("_becomeImplementation(bytes)", becomeImplementationData));

        emit NewImplementation(oldImplementation, implementation);
    }

    /**
     * @notice Sender supplies assets into the market and receives cTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    // 存款合约 存钱
    // 使用erc20资产转入ctoken合约中，然后根据`最新的汇率(兑换率)`兑换对应ctoken的数量转入调用者地址中。
    function mint(uint mintAmount) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("mint(uint256)", mintAmount));
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender redeems cTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of cTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    // 赎回存款 取钱    取出全部资产
    // 将ctoken转换为存入的erc20，会根据当前`最新兑换率`兑换可以兑换资产。
    function redeem(uint redeemTokens) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("redeem(uint256)", redeemTokens));
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    // 赎回存款 取钱
    //  取出 指定资产的数量。会根据兑换率算出需要扣除多少ctoken能对换多少token
    // 比如现在有100我需要取出20
    function redeemUnderlying(uint redeemAmount) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("redeemUnderlying(uint256)", redeemAmount));
        return abi.decode(data, (uint));
    }

    /**
       * @notice 发件人从协议中借用资产到他们自己的地址
       * @param borrowAmount 要借入的标的资产的数量
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    //  借款
    // 根据用户抵押资产来计算能兑换多少可借额度。借款成功会将资产池中的资产转入调用者钱包中。
    function borrow(uint borrowAmount) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("borrow(uint256)", borrowAmount));
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    // 还款
    // 当指定额度为-1时，表示全额还款（还款额度，利息），否则会存在没有还完，因为每个区块都会产生利息uint(-1)
    function repayBorrow(uint repayAmount) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("repayBorrow(uint256)", repayAmount));
        return abi.decode(data, (uint));
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    // 代还款 支付人帮借款人还款
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("repayBorrowBehalf(address,uint256)", borrower, repayAmount));
        return abi.decode(data, (uint));
    }


    /**
      * @notice 发件人清算借款人的抵押品。
      * 扣押的抵押品被转移给清算人。
      * @param borrower 要清算的cToken的借款人
      * @param cTokenCollateral 从借款人那里获取抵押品的市场
      * @param repayAmount 需要偿还的标的借入资产的数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    // 清算
    // 任何人都能调用这个函数，调用可以承当 清算人、直接借款人、还款金额、清算的ctoken资产。
    // 清算人帮借款人还款时，可以得到借款人所抵押的 等价值+清算奖励的ctoken资产
    function liquidateBorrow(address borrower, uint repayAmount, CTokenInterface cTokenCollateral) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("liquidateBorrow(address,uint256,address)", borrower, repayAmount, cTokenCollateral));
        return abi.decode(data, (uint));
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint amount) external returns (bool) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("transfer(address,uint256)", dst, amount));
        return abi.decode(data, (bool));
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address src, address dst, uint256 amount) external returns (bool) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("transferFrom(address,address,uint256)", src, dst, amount));
        return abi.decode(data, (bool));
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
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        return abi.decode(data, (bool));
    }

    /**
     * @notice Get the current allowance from `owner` for `spender`
     * @param owner The address of the account which owns the tokens to be spent
     * @param spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (-1 means infinite)
     */
    function allowance(address owner, address spender) external view returns (uint) {
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("allowance(address,address)", owner, spender));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 获取`owner`的代币余额
      * @param owner 要查询的账户地址
      * @return `owner` 拥有的代币数量
      */
    function balanceOf(address owner) external view returns (uint) {
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("balanceOf(address)", owner));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 获取`owner`的底层余额
      * @dev 这也会在交易中产生利息
      * @param owner 要查询的账户地址
      * @return `owner` 拥有的底层证券数量
      */
    //  获取供应余额
    function balanceOfUnderlying(address owner) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("balanceOfUnderlying(address)", owner));
        console.log("abi.decode(data, (uint)",abi.decode(data, (uint)));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 获取账户余额的快照，以及缓存的汇率
      * @dev 这被主计长用来更有效地执行流动性检查。
      * @param account 要快照的账户地址
      */
    //  @return （可能的错误，代币余额，借入余额，汇率尾数）

    //  代币余额，借入余额，汇率尾数
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint) {
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("getAccountSnapshot(address)", account));
        return abi.decode(data, (uint, uint, uint, uint));
    }

    /**
      * @notice 返回当前每个区块的供应量/**
      * @notice 返回此 cToken 的当前每块借入利率
      *此 cToken 的价格
      * @return 每个区块的供应利率，按 1e18 缩放
      */
    // 获取每个区块的贷款(借款)汇率
    function borrowRatePerBlock() external view returns (uint) {
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("borrowRatePerBlock()"));
        return abi.decode(data, (uint));
    }

   /**
      * @notice 返回此 cToken 的当前每块供应利率
      */
    //   * @return 每个区块的供应利率，按 1e18 缩放
    // 获取每个区块的供应利率
    function supplyRatePerBlock() external view returns (uint) {
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("supplyRatePerBlock()"));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 返回当前总借款加上应计利息
      */
    //   * @return 有息借款总额
    // 当前总贷款额度
    function totalBorrowsCurrent() external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("totalBorrowsCurrent()"));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 对更新的borrowIndex 产生利息，然后使用更新的borrowIndex 计算账户的借入余额
      * @param account 更新borrowIndex后需要计算余额的地址
      */
    //   * @return 计算的余额
    function borrowBalanceCurrent(address account) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("borrowBalanceCurrent(address)", account));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 根据存储的数据返回账户的借入余额
      * @param account 需要计算余额的地址
      */
    //   * @return 计算的余额
    //  获取输入用户的借款额度
    function borrowBalanceStored(address account) public view returns (uint) {
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("borrowBalanceStored(address)", account));
        return abi.decode(data, (uint));
    }

   /**
      * @notice 累积利息然后返回最新汇率
      */
    //   * @return 按 1e18 比例计算的汇率
    // 最新存款汇率
    function exchangeRateCurrent() public returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("exchangeRateCurrent()"));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 计算从底层证券到 CToken 的汇率
      * @dev 这个函数在计算汇率之前不会产生利息
      */
    //   * @return 按 1e18 比例计算的汇率
    //  获取存款汇率
    function exchangeRateStored() public view returns (uint) {
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("exchangeRateStored()"));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 获取该cToken在标的资产中的现金余额
      */
    //   * @return 该合约拥有的标的资产数量
    function getCash() external view returns (uint) {
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("getCash()"));
        return abi.decode(data, (uint));
    }

    /**
       * @notice 将应计利息应用于总借款和准备金。
       * @dev 这计算从最后一个检查点块产生的利息
       * 直到当前块并将新的检查点写入存储。
       */
    //  计算新的利息
    function accrueInterest() public returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("accrueInterest()"));
        // console.log("abi.decode(data, (uint))", abi.decode(data, (uint)));
        return abi.decode(data, (uint));
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
    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("seize(address,address,uint256)", liquidator, borrower, seizeTokens));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 将 ERC-20 意外转移到此合约的公共功能。 令牌发送给管理员（时间锁）
      * @param token 要扫描的 ERC-20 代币的地址
      */
    //  Compound发起新提案037
    // cUNI被意外地发送到cUNI合约中，后升级这个方法。把意外转移的代币转移到admin中
    function sweepToken(EIP20NonStandardInterface token) external {
        delegateToImplementation(abi.encodeWithSignature("sweepToken(address)", token));
    }


    /*** Admin Functions ***/

    /**
       * @notice 开始转移管理员权限。 newPendingAdmin 必须调用 `_acceptAdmin` 来完成传输。
       * @dev 管理员功能开始更改管理员。 newPendingAdmin 必须调用 `_acceptAdmin` 来完成传输。
       * @param newPendingAdmin 新的待处理管理员。
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    function _setPendingAdmin(address payable newPendingAdmin) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("_setPendingAdmin(address)", newPendingAdmin));
        return abi.decode(data, (uint));
    }

    /**
       * @notice 为市场设置新的审计员
       * @dev 管理员功能设置一个新的审计员
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    function _setComptroller(ComptrollerInterface newComptroller) public returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("_setComptroller(address)", newComptroller));
        return abi.decode(data, (uint));
    }

    /**
       * @notice 产生利息并使用 _setReserveFactorFresh 为协议设置一个新的储备因子
       * @dev 管理函数来产生利息并设置一个新的储备因子
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    //  设置保证金系数
    function _setReserveFactor(uint newReserveFactorMantissa) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("_setReserveFactor(uint256)", newReserveFactorMantissa));
        return abi.decode(data, (uint));
    }

    /**
       * @notice 接受管理员权限的转移。 msg.sender 必须是 pendingAdmin
       * @dev 管理员功能，用于待定管理员接受角色并更新管理员
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    function _acceptAdmin() external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("_acceptAdmin()"));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 通过从管理员转移产生利息并增加准备金
      * @param addAmount 要添加的储备量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    function _addReserves(uint addAmount) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("_addReserves(uint256)", addAmount));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 通过转移到管理员来产生利息并减少准备金
      * @param reduceAmount 减少到准备金的数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    function _reduceReserves(uint reduceAmount) external returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("_reduceReserves(uint256)", reduceAmount));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 产生利息并使用 _setInterestRateModelFresh 更新利率模型
      * @dev 管理功能来产生利息和更新利率模型
      * @param newInterestRateModel 要使用的新利率模型
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    // 设置利率模型
    function _setInterestRateModel(InterestRateModel newInterestRateModel) public returns (uint) {
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("_setInterestRateModel(address)", newInterestRateModel));
        return abi.decode(data, (uint));
    }

    /**
      * @notice 将执行委托给另一个合约的内部方法
      * @dev 无论实现返回或转发还原，它都会返回给外部调用者
      * @param callee 委托调用的合约
      * @param data 要委托调用的原始数据
      */
    //   * @return 委托调用返回的字节数
    function delegateTo(address callee, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = callee.delegatecall(data);
        // cconsole.log("success", success);
        // console.log("returnData", returnData);
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize)
            }
        }
        return returnData;
    }

    /**
      * @notice 将执行委托给实现合约
      * @dev 无论实现返回或转发还原，它都会返回给外部调用者
      * @param data 要委托调用的原始数据
      */
    //   * @return 委托调用返回的字节数
    //  指定委托调用的方法
    function delegateToImplementation(bytes memory data) public returns (bytes memory) {
        return delegateTo(implementation, data);
    }

    /**
      * @notice 将执行委托给实现合约
      * @dev 无论实现返回或转发还原，它都会返回给外部调用者
      * 包装器返回数据中还有额外的 2 个前缀 uint，我们忽略它们，因为我们做了一个额外的跃点。
      * @param data 要委托调用的原始数据
      */
    //   * @return 委托调用返回的字节数
    function delegateToViewImplementation(bytes memory data) public view returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).staticcall(abi.encodeWithSignature("delegateToImplementation(bytes)", data));
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize)
            }
        }
        return abi.decode(returnData, (bytes));
    }

    /**
      * @notice 将执行委托给实现合约
      * @dev 无论实现返回或转发还原，它都会返回给外部调用者
      */
    function () external payable {
        require(msg.value == 0,"CErc20Delegator:fallback: cannot send value to fallback");

        // delegate all other functions to current implementation
        (bool success, ) = implementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize)

            switch success
            case 0 { revert(free_mem_ptr, returndatasize) }
            default { return(free_mem_ptr, returndatasize) }
        }
    }
}

pragma solidity ^0.5.16;

import "./CToken.sol";
import "hardhat/console.sol";

interface CompLike {
  function delegate(address delegatee) external;
}

/**
 * @title Compound's CErc20 Contract
 * @notice CTokens which wrap an EIP-20 underlying
 * @author Compound
 */
// 在早期版本中，CErc20 也是用户交互的入口合约，但后来做了调整，
// CErc20 移除了构造函数，改为了初始化函数，改为了初始化函数，
// 增加了 CErc20Delegate 作为其上层合约，
// 而且还增加了 CErc20Delegator 来代理 CToken，作为 cToken 的入口合约。
contract CErc20 is CToken, CErc20Interface {
    /**
      * @notice 初始化新的货币市场
      * @param underlying_ 标的资产地址
      * @param comptroller_ 主计长地址
      * @param interestRateModel_ 利率模型的地址
      * @param initialExchangeRateMantissa_ 初始汇率，按 1e18 缩放
      * @param name_ 此令牌的 ERC-20 名称
      * @param symbol_ 此代币的 ERC-20 符号
      * @param decimals_ 此令牌的 ERC-20 十进制精度
      */
    function initialize(
        address underlying_,
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        // CToken initialize does the bulk of the work
        // 初始化cToken
        super.initialize(
            comptroller_, 
            interestRateModel_, 
            initialExchangeRateMantissa_, 
            name_, 
            symbol_, 
            decimals_
        );

        // Set underlying and sanity check it
        console.log("underlying_", underlying_);
        underlying = underlying_;

        // 获取余额干啥 ？？？
        EIP20Interface(underlying).totalSupply();
    }

    /*** User Interface ***/
// 存款
// 取款
// 借钱 需要先存款 只能借处存款额度的__
// 还钱
// 清算
    /**
      * @notice 发件人向市场提供资产并接收 cToken 作为交换
      * @dev 无论操作成功与否都会产生利息，除非还原
      * @param mintAmount 要供应的标的资产的数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    // 存款：发送token到合约换取cToken
    function mint(uint mintAmount) external returns (uint) {
        (uint err,) = mintInternal(mintAmount);
        return err;
    }

    /**
      * @notice 发件人赎回 cToken 以换取基础资产
      * @dev 无论操作成功与否都会产生利息，除非还原
      * @param redeemTokens 要赎回底层证券的 cToken 数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    // 取款：取出全部存款
    function redeem(uint redeemTokens) external returns (uint) {
        return redeemInternal(redeemTokens);
    }

    /**
      * @notice 发件人赎回 cToken 以换取指定数量的基础资产
      * @dev 无论操作成功与否都会产生利息，除非还原
      * @param redeemAmount 要赎回的底层证券数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    // 取款：取出指定数量的token
    function redeemUnderlying(uint redeemAmount) external returns (uint) {
        return redeemUnderlyingInternal(redeemAmount);
    }

    /**
       * @notice 发件人从协议中借用资产到他们自己的地址
       * @param borrowAmount 要借入的标的资产的数量
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    //  借钱
    function borrow(uint borrowAmount) external returns (uint) {
        return borrowInternal(borrowAmount);
    }

    /**
      * @notice 发件人偿还自己的借款
      * @param repayAmount 还款金额
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    //  还钱：自己还自己
    // uint(-1) 为全部还款， 否则为指定额度
    function repayBorrow(uint repayAmount) external returns (uint) {
        (uint err,) = repayBorrowInternal(repayAmount);
        return err;
    }

    /**
      * @notice 发件人偿还属于借款人的借款
      * @param borrower 还清债务的账户
      * @param repayAmount 还款金额
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    // 还款：我帮别人还
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint) {
        (uint err,) = repayBorrowBehalfInternal(borrower, repayAmount);
        return err;
    }

    /**
      * @notice 发件人清算借款人的抵押品。
      * 被扣押的抵押品被转移给清算人。
      * @param borrower 该cToken的要被清算的借款人
      * @param repayAmount 要偿还的标的借入资产的金额
      * @param cTokenCollateral 从借款人那里获取抵押品的市场
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    // 清算： 清算别人资产 之多50%
    function liquidateBorrow(address borrower, uint repayAmount, CTokenInterface cTokenCollateral) external returns (uint) {
        (uint err,) = liquidateBorrowInternal(borrower, repayAmount, cTokenCollateral);
        return err;
    }

    /**
      * @notice 将 ERC-20 意外转移到此合约的公共功能。 令牌发送给管理员（时间锁）
      * @param token 要扫描的 ERC-20 代币的地址
      */
    //  Compound发起新提案037
    // cUNI被意外地发送到cUNI合约中，后升级这个方法。把意外转移的代币转移到admin中
    function sweepToken(EIP20NonStandardInterface token) external {
        console.log("underlying address:", underlying);
    	require(address(token) != underlying, "CErc20::sweepToken: can not sweep underlying token");
    	uint256 balance = token.balanceOf(address(this));   //  当前合约有多长token
    	token.transfer(admin, balance);//   转移到admin地址
    }

    /**
      * @notice 发件人添加到储备中。
      * @param addAmount 要添加为储备的基础代币的数量
      * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
      */
    //  admin 添加储备金 
    function _addReserves(uint addAmount) external returns (uint) {
        return _addReservesInternal(addAmount);
    }

    /*** Safe Token ***/

    /**
      * @notice 获取该合约在底层证券方面的余额
      * @dev 这不包括当前消息的值，如果有的话
      * @return 该合约拥有的底层代币数量
      */
    function getCashPrior() internal view returns (uint) {
        EIP20Interface token = EIP20Interface(underlying);
        return token.balanceOf(address(this));
    }

    /**
      * @dev 类似于 EIP20 传输，除了它处理来自 `transferFrom` 的 False 结果并在这种情况下恢复。
      * 这将由于余额不足或津贴不足而恢复。
      * 此函数返回实际收到的金额，
      * 如果转账有附加费用，则可能小于“金额”。
      *
      * 注意：此包装器安全地处理不返回值的非标准 ERC-20 令牌。
      * 见这里：https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
      */
    //  ERC20 transferFrom。 form => contract
    // form 地址转账token到当前合约。返回转账了多少token额度到当前合约
    function doTransferIn(
      address from, //  从这个账户中还款
      uint amount   //  还款数量
    ) internal returns (uint) {
        //  类似一个ERC20的接口
        // 利用erc20接口获取标的资产的合约
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        // ERC20接口 获取当前合约中cToken的余额
        uint balanceBefore = EIP20Interface(underlying).balanceOf(address(this));
		    console.log("标的资产的额度",underlying,balanceBefore);
        // addres => contract 指定数量cToken
        //  还款账户合约转移指定数量的cToken
        // 从form地址转转帐(标的资产)指定额度到当前合约中。
        token.transferFrom(from, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {                       // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                      // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of external call
                }
                default {                      // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        // 转账成功检测
        require(success, "TOKEN_TRANSFER_IN_FAILED");

        // 获取当前合约最新余额
        uint balanceAfter = EIP20Interface(underlying).balanceOf(address(this));
		  
        //  检查最新额度必须大于原有额度
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        // 返回这次新增了多少额度
        return balanceAfter - balanceBefore;   // underflow already checked above, just subtract
    }

    /**
      * @dev 类似于 EIP20 传输，除了它处理来自 `transfer` 的 False 成功并返回解释
      * 错误代码而不是还原。 如果调用者没有调用检查协议的余额，这可能会由于以下原因而恢复
      * 本合同持有的现金不足。 如果调用者在此调用之前检查了协议的余额，并已验证
      * 它 >= 数量，在正常情况下不应恢复。
      *
      * 注意：此包装器安全地处理不返回值的非标准 ERC-20 令牌。
      * 见这里：https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
      */
    // ERC20 transfer。 contract => to
    function doTransferOut(address payable to, uint amount) internal {
        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        token.transfer(to, amount);

        bool success;
        assembly {
            switch returndatasize()
                case 0 {                      // This is a non-standard ERC-20
                    success := not(0)          // set success to true
                }
                case 32 {                     // This is a compliant ERC-20
                    returndatacopy(0, 0, 32)
                    success := mload(0)        // Set `success = returndata` of external call
                }
                default {                     // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
        require(success, "TOKEN_TRANSFER_OUT_FAILED");
    }

    /**
     * @notice 管理员调用以委托类似 COMP 底层的投票
     * @param compLikeDelegatee 将投票委托给的地址
     * @dev CTokens 其底层不是 CompLike 应该在此处恢复
     */
    function _delegateCompLikeTo(address compLikeDelegatee) external {
        require(msg.sender == admin, "only the admin may set the comp-like delegate");
        CompLike(underlying).delegate(compLikeDelegatee);
    }
}

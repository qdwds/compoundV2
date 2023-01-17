pragma solidity ^0.5.16;

import "./ComptrollerInterface.sol";
import "./InterestRateModel.sol";
import "./EIP20NonStandardInterface.sol";

// 汇率 exchangeRate = (getCash() + totalBorrows() - totalReserves()) / totalSupply()
contract CTokenStorage {
    /**
     * @dev 重新进入检查的保护变量
     */
    bool internal _notEntered;

    /**
     * @notice EIP-20 token name for this token
     */
    string public name;

    /**
     * @notice EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint8 public decimals;

    /**
      * @notice 可以应用的最大借贷利率（.0005%/块）
      */
    //  最大借款利率
    uint internal constant borrowRateMaxMantissa = 0.0005e16;

    /**
     * @notice Maximum fraction of interest that can be set aside for reserves
     */
    // 储备利率 100%
    uint internal constant reserveFactorMaxMantissa = 1e18;

    /**
     * @notice 管理员
     */
    address payable public admin;

    /**
     * @notice 管理员
     */
    address payable public pendingAdmin;

    /**
     * @notice cToken的操作(控制器)的合约
     */
    ComptrollerInterface public comptroller;

    /**
     * @notice Model which tells what the current interest rate should be
     */
    // 利率模型
    // mainnet.json
    InterestRateModel public interestRateModel;

    /**
     * @notice 铸造第一个 CToken 时使用的初始汇率（当 totalSupply = 0 时使用）
     */
    // 汇率
    uint internal initialExchangeRateMantissa;

    /**
     * @notice Fraction of interest currently set aside for reserves
     * 市场储备金的利率
     */
    uint public reserveFactorMantissa;

    /**
     * @notice 上一次计算过利息的区块
     */
    uint public accrualBlockNumber;

    /**
     * @notice 自市场开放以来总赚取利率的累计值()
     * 初始化为 1e18
     * 指标
     */
    uint public borrowIndex;

    /**
     * @notice 该市场标的资产的未偿还借款总额 = 市场总借款额度
     */

    uint public totalBorrows;

    /**
     * @notice 在该市场持有的标的资产储备金总额
     */
    // 精度为 underlying asseet 的精度
    uint public totalReserves;  //  市场总储备金

    /**
     * @notice 流通中的代币总数 cToken
     */
    uint public totalSupply;

    /**
     * @notice 每个账户的代币余额的官方记录 记录用户存款余额
     */
    // 
    mapping (address => uint) internal accountTokens;

    /**
     * @notice 代表他人批准的代币转账金额 授权额度
     */
    mapping (address => mapping (address => uint)) internal transferAllowances;

   /**
      * @notice 借入余额信息的容器
      * @member principal 总余额（包括应计利息），在应用最近的余额更改操作后
      * @member interestIndex 全球借贷指数截至最近的余额变化行动
    */
    struct BorrowSnapshot {
        uint principal; //  借款总额度( +利息)
        uint interestIndex; //  记录借款指数
    }

    /**
     * @notice 将账户地址映射到未偿借款余额
     */
    // 借款人 未偿还的贷款额度 == 借款人 借款额度
    mapping(address => BorrowSnapshot) internal accountBorrows;

    /**
     * @notice 被扣押的抵押品的份额被添加到准备金中
     */
    uint public constant protocolSeizeShareMantissa = 2.8e16; //2.8%

}

contract CTokenInterface is CTokenStorage {
    /**
     * @notice Indicator that this is a CToken contract (for inspection)
     */
    bool public constant isCToken = true;


    /*** Market Events ***/

    /**
     * @notice Event emitted when interest is accrued
     */
    event AccrueInterest(uint cashPrior, uint interestAccumulated, uint borrowIndex, uint totalBorrows);

    /**
     * @notice Event emitted when tokens are minted
     */
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /**
     * @notice Event emitted when underlying is borrowed
     */
    event Borrow(address borrower, uint borrowAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is liquidated
     */
    event LiquidateBorrow(address liquidator, address borrower, uint repayAmount, address cTokenCollateral, uint seizeTokens);


    /*** Admin Events ***/

    /**
     * @notice Event emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Event emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    /**
     * @notice Event emitted when comptroller is changed
     */
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice Event emitted when interestRateModel is changed
     */
    event NewMarketInterestRateModel(InterestRateModel oldInterestRateModel, InterestRateModel newInterestRateModel);

    /**
     * @notice Event emitted when the reserve factor is changed
     */
    event NewReserveFactor(uint oldReserveFactorMantissa, uint newReserveFactorMantissa);

    /**
     * @notice Event emitted when the reserves are added
     */
    event ReservesAdded(address benefactor, uint addAmount, uint newTotalReserves);

    /**
     * @notice Event emitted when the reserves are reduced
     */
    event ReservesReduced(address admin, uint reduceAmount, uint newTotalReserves);

    /**
     * @notice EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint amount);

    /**
     * @notice EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint amount);

    /**
     * @notice Failure event
     */
    event Failure(uint error, uint info, uint detail);

    //  自己添加，获取当前用户标的资产的数量
    event BalanceOfUnderlying(uint balance);
    /*** User Interface ***/

    function transfer(address dst, uint amount) external returns (bool);
    function transferFrom(address src, address dst, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    // 资产基础余额
    function balanceOfUnderlying(address owner) external returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    // 借款利率
    function borrowRatePerBlock() external view returns (uint);
    // 市场供应率
    function supplyRatePerBlock() external view returns (uint);
    // 市场总借款
    function totalBorrowsCurrent() external returns (uint);
    // 借款余额
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrowBalanceStored(address account) public view returns (uint);
    // cToken <-> Token 兑换率
    function exchangeRateCurrent() public returns (uint);
    function exchangeRateStored() public view returns (uint);
    // 市场中的基础余额
    function getCash() external view returns (uint);
    function accrueInterest() public returns (uint);
    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);


    /*** Admin Functions ***/

    function _setPendingAdmin(address payable newPendingAdmin) external returns (uint);
    function _acceptAdmin() external returns (uint);
    function _setComptroller(ComptrollerInterface newComptroller) public returns (uint);
    function _setReserveFactor(uint newReserveFactorMantissa) external returns (uint);
    function _reduceReserves(uint reduceAmount) external returns (uint);
    function _setInterestRateModel(InterestRateModel newInterestRateModel) public returns (uint);
}

contract CErc20Storage {
    /**
     *@notice 此 CToken 的基础资产
    */
    address public underlying;
}

contract CErc20Interface is CErc20Storage {

    /*** User Interface ***/
    // 存款
    function mint(uint mintAmount) external returns (uint);
    // 取款 按cToken数量取
    function redeem(uint redeemTokens) external returns (uint);
    // 取款 按标的资产取数量取
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    // 借款
    function borrow(uint borrowAmount) external returns (uint);
    // 自己还款
    function repayBorrow(uint repayAmount) external returns (uint);
    // 我帮别人还款
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    // 清算
    function liquidateBorrow(address borrower, uint repayAmount, CTokenInterface cTokenCollateral) external returns (uint);
    function sweepToken(EIP20NonStandardInterface token) external;


    /*** Admin Functions ***/

    function _addReserves(uint addAmount) external returns (uint);
}

contract CDelegationStorage {
    /**
     * @notice 当前合约的执行地址
     */
    address public implementation;
}

contract CDelegatorInterface is CDelegationStorage {
    /**
     * @notice Emitted when implementation is changed
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @notice Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation
     * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
     */
    function _setImplementation(address implementation_, bool allowResign, bytes memory becomeImplementationData) public;
}

contract CDelegateInterface is CDelegationStorage {
    /**
     * @notice Called by the delegator on a delegate to initialize it for duty
     * @dev Should revert if any issues arise which make it unfit for delegation
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes memory data) public;

    /**
     * @notice Called by the delegator on a delegate to forfeit its responsibility
     */
    function _resignImplementation() public;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner() {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
      
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

// This token contract have some additional unique features of HappyInu App. 
// Below I will describe three main functions. I will also add comments on the contract code.

// - register(string calldata ava, string calldata uname, address referrer) - User becoming app member using this function. All additional features only for registered users.
//        ava      - Required parameter, Url link to users's avatar image. This struct parameter can be changed within updateProfile() function
//        uname    - Required parameter, Unique username. This struct parameter can be changed within updateProfile() function. Uniqueness is checked using uniqueUnames mapping
//        referrer - Required parameter, The contract integrates a system of referral rewards, which we charge from taxes. The user must fill in the address of the person who invited him or choose randomly. 
//                   Random functionality will work on the dapp side. When interacting directly with a contract, the address must be filled in manually. Addresses of registered members can be found in userIndex mapping.


// - createWish(uint256 totalAmount) - Users can add theirs wishes into contract usins this function
//        totalAmount - required parameter, Amount of tokens needed to make wish come true


// - donate(uint256 wishID, uint256 a, bool personalBalance) - Users can donate any amount of tokens to any wish using this function 
//        wishID -  required parameter, index number of the wish for which user will donate. The parameter is filled in automatically when interacting with the dapp. When interacting directly with a contract, the index number must be filled in manually. 
//                  All wishes stores in wishes mapping by index number. The total number of wishes is stored in the wishesCount variable.
//        a      -  required parameter, Amount of donation in tokens.
//        personalBalance - required parameter, Determines whether the donation is paid from personal balance or not. Personal balance amount stores in users struct (users mapping)
//                          User can get his personal balance only by returning a donation from expired wish. The personal balance is replenished automatically when the wish the user has donated has expired (The time that has passed since the creation of the wish is more than wishesClaimPeriod in seconds and wish have not reached minimal amount of tokens)



// Users structure. Every new user stores in users mapping by address.
struct User {
    uint256 time; // timestamp of registration
    string ava; // avatar url
    string uname; // unique username
    address referrer; // referrer address
    uint256 donatesAmount; // total users actual donations (donations that participate in reward programs)  
    uint256 oldDonatesAmount; // total user donations for all time minus donatesAmount
    uint256 premiumTime; // timestamp until which the premium is valid
    uint256 payoutAmountSimple; // referral rewards without premium account
    uint256 payoutAmountPremium; // referral rewards only for premium account
    uint256 personalBalance; // personal balance of returned donations
    uint256 referralCount; // Number of referrals
}


// Wish structure. Every new wish stores in wishes mapping by index number.
struct Wish {
    uint256 time; // timestamp of wish creation
    uint256 amount; // current donations amount in tokens (can be higher than tAmount)
    uint256 tAmount; // needed donations amount in tokens
    bool claimed; // shows whether the owner of the wish has taken the tokens
    uint256 donatorsCount; // number of unique wish donators;
    address owner; // owner address;
}

contract HappyInu is Context, IERC20, Ownable {
    mapping (address => User) public users; // mapping that stores all registered members
    mapping (uint256 => address) public usersIndex; // mapping that stores indexes of registered members
    uint256 public totalMembers = 0; //number of all registered members
    mapping (string => bool) public uniqueUnames; // mapping to check uniqeness of username

    uint256 public distributionCount = 0; // number of wallets that recieves taxes
    mapping (uint256 => uint256) public distribution; // mapping that stores percentages of taxes for distribution wallets by wallet index
    mapping (uint256 => address) public distributionIndex; // mapping that stores addresses of distribution wallets by wallet index

    address public routerAddress;

    uint256 public premiumPrice = 200; // price for premium account on 30 days
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    address payable public TreasuryWallet;
    address public FirstUserAddress; // This variable will store the address of the first referrer
    uint8 private constant _decimals = 18;
    uint256 private constant _tTotal = 7_777_777 * 10**_decimals; 
    string private constant _name = "HappyInu";
    string private constant _symbol = "HAPPY";
    uint256 private _minSwapTokens = 100 * 10**_decimals; 
    uint256 private _maxSwapTokens = 300 * 10**_decimals; 
    uint256 public buyTaxes = 3;
    uint256 public sellTaxes = 3;
    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool public tradeEnable = false;
    bool private _SwapBackEnable = false;
    bool private inSwap = false;

    address wishesWallet = 0x94fb58692B6b3F5Ee957B5089c5373427a5dee29; // address of wallet where donations of wishes stores before claim
    address mlmWallet = 0x50F1623D4e91b55e7833ab9c6C9213d21b571c8d; // address of wallet where referral rewards stores before claim
    address public constant deadWallet = 0x000000000000000000000000000000000000dEaD;
    
    mapping(address => mapping (uint256 => address)) public referrals; // this mapping stores wallet's referrals addresses by index
    mapping(address => mapping (address => uint256)) private referralsAmounts; // this mapping stores reward amount from custom referral

    event Registration(address indexed member, address indexed referrer);
    event Payout(address indexed to, uint256 amount);

    modifier onlyMembers() {
        require(isMember(_msgSender()), "Only registered members can call this function");
        _;
    }

    modifier onlyPremium() {
        require(isPremium(_msgSender()), "Only Premium has access");
        _;
    }

    modifier notBanned() {
        require(!banSnipers[_msgSender()], "You have banned for sniping");
        _;
    }

    event ERC20TokensRecovered(uint256 indexed _amount);
    event ETHBalanceRecovered();
    event wishCreated(uint256 indexed wishID, uint256 indexed wishAmount);
    event wishClaimed(uint256 indexed wishID, uint256 indexed wishAmount, uint256 indexed timestamp);

    mapping (uint256 => Wish) public wishes; // this mapping stores all wishes by index
    uint256 public wishesClaimPeriod = 60 * 60 * 24 * 30; // this mapping stores the number of seconds within which the desire is active

    uint256 public wishesCount = 0; // number of all wishes
    uint256 public createWishPrice = 30; // price of wish creation in tokens

    uint256 public holdersCount = 0; // number of all holders (user can be holder but not registered member)
    uint256 public donatorsCount = 0; // number of all donators
    mapping (uint256 => address) public donatorsIndex; // this mapping stores addresses of donators by index
    mapping (uint256 => address) public holdersIndex; // this mapping stores addresses of holders by index
    mapping (address => bool) public isHolder; // this mapping checks whether the user is holder or not
    mapping (address => bool) public excludeFromHolders; // this mapping checks whether the wallet is taken into account in calculating the sum of all tokens held by holders
    mapping (address => bool) public banSnipers; // this mapping checks whether the address is banned, it only works for the first 7 days after deployment

    uint256 public totalDonatesAmount = 0; // the sum of all donations made for the current reward period
    uint256 public totalDonatesAmountCurrent = 0; // the sum of all donations made by all time minus totalDonatesAmount
    mapping (uint256 => mapping(address => bool)) public isWishDonator; // this mapping checks whether a specific address is a wish donator
    mapping (uint256 => mapping(uint256 => address)) public wishDonatorIndex; // this mapping stores address of donators for wish by index
    mapping (uint256 => mapping(address => uint256)) public wishDonatorAmount; // this mapping stores amounts of wish donations by address
    mapping (uint256 => mapping(address => bool)) public isWishDonatorAmountReturned; // this mapping checks whether the donation is returned to the personal balance if the wish has expired
    uint256 private numberDonatorsReturnTx = 3; // Number of donators per transaction who will receive the personal balance returns

    event FeesUpdated(uint256 indexed _feeAmount);
    event ExcludeFromFeeUpdated(address indexed account);
    event includeFromFeeUpdated(address indexed account);
    event FeesRecieverUpdated(address indexed _newWallet);
    event SwapThreshouldUpdated(uint256 indexed minToken, uint256 indexed maxToken);
    event SwapBackSettingUpdated(bool indexed state);
    event TradingOpenUpdated();
    event PremiumPaid(address indexed account);
    event NewDonate(address indexed account, uint256 indexed amount, uint256 indexed wishID);
    event TaxesChanged(uint256 indexed buyTax, uint256 indexed sellTax);

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor () {
        if (block.chainid == 56){
            routerAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // PCS BSC Mainnet Router
        } else if (block.chainid == 97){
            routerAddress = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1; // PCS BSC Testnet PinkSale Router
        } 

        uniswapV2Router = IUniswapV2Router02(routerAddress);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        excludeFromHolders[uniswapV2Pair] = true;
        excludeFromHolders[routerAddress] = true;

        TreasuryWallet = payable(0x6E242A50F329aF63bFC42eB23C2888E0D5F43275);
        excludeFromHolders[TreasuryWallet] = true;
        _isExcludedFromFee[_msgSender()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[TreasuryWallet] = true;
        _isExcludedFromFee[deadWallet] = true;
        _isExcludedFromFee[0x407993575c91ce7643a4d4cCACc9A98c36eE1BBE] = true; // BSC PinkSale Lock
        excludeFromHolders[_msgSender()] = true;
        excludeFromHolders[address(this)] = true;
        excludeFromHolders[TreasuryWallet] = true;
        excludeFromHolders[deadWallet] = true;
        excludeFromHolders[0x407993575c91ce7643a4d4cCACc9A98c36eE1BBE] = true; // BSC PinkSale Lock
    
        _balances[_msgSender()] = _tTotal;
        emit Transfer(address(0), _msgSender(), _tTotal);

        excludeFromHolders[mlmWallet] = true;
        excludeFromHolders[wishesWallet] = true;

        distribution[0] = 80;
        distribution[1] = 20;
        distributionCount = 2;
        distributionIndex[0] = address(this);
        distributionIndex[1] = mlmWallet;


        // registration of first referrer
        FirstUserAddress = TreasuryWallet;
        string memory u = "mrluci";
        users[FirstUserAddress] = User(block.timestamp, "https://i.ibb.co/RCJDqXP/image.jpg", u, address(0), 0, 0, block.timestamp, 0, 0, 0, 0);
        uniqueUnames[u] = true;
        usersIndex[totalMembers] = FirstUserAddress;
        totalMembers++;
    }


    // this function changes wishesWallet or mlmWallet and transfers tokens to new addresses
    function changeServiceWallet(address addr, bool mlm) external onlyOwner {
        address old = mlm ? mlmWallet : wishesWallet;
        excludeFromHolders[old] = false;
        excludeFromHolders[addr] = true;
        if(mlm){
            mlmWallet = addr;
        } else {
            wishesWallet = addr;
        }
        uint256 a = _balances[old];
        _balances[addr] += a;
        _balances[old] = 0;
        emit Transfer(old, addr, a);
    }

    function setNewRouter(address addr) external onlyOwner {
        uniswapV2Router = IUniswapV2Router02(addr);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        excludeFromHolders[uniswapV2Pair] = true;
        excludeFromHolders[addr] = true;
    }

    // this function checks whether it is the first week since deployment
    function isFirstWeek() public view returns (bool) {
        return (users[FirstUserAddress].time + (60 * 60 * 24 * 7)) > block.timestamp;
    }

    // this function adds wallet to ban on first week
    function addSniperToBan(address wallet) external onlyOwner {
        require(isFirstWeek(), "You only can ban sniper in first week");
        banSnipers[wallet] = true;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal - _balances[deadWallet];
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function transfer(address recipient, uint256 amount) public notBanned returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public notBanned returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public notBanned returns (bool) {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // this function send taxes to distribution wallets
    function sendTaxes(address from, address to, uint256 feesum) internal {
        for(uint256 i = 0; i < distributionCount; i++) {
            uint256 sum = feesum * distribution[i] / 100;
            _balances[distributionIndex[i]] += sum;
            emit Transfer(from, distributionIndex[i], sum);
            if(address(mlmWallet) == address(distributionIndex[i])){
                addBonus(from, to, sum);
            }
        }
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 feesum = 0;

        if (!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {    
            require(tradeEnable, "Trading not enabled");  
            feesum = amount * buyTaxes / 100;
        }
        
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            feesum = 0;
        } 
        
        if (to == uniswapV2Pair && from != address(this) && !_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            feesum = amount * sellTaxes / 100;    
        }
       
        uint256 contractTokenBalance = balanceOf(address(this));
        if (!inSwap && from != uniswapV2Pair && _SwapBackEnable && contractTokenBalance > _minSwapTokens) {
            swapTokensForEth(min(amount, min(contractTokenBalance, _maxSwapTokens)));
            uint256 contractETHBalance = address(this).balance;
            if(contractETHBalance > 0) {
                sendETHToFee(address(this).balance);
            }
        }
        
        _balances[from] = _balances[from] - amount; 
        _balances[to] = _balances[to] + (amount - (feesum));
        emit Transfer(from, to, amount - (feesum));
        
        if(feesum > 0){
            sendTaxes(from, to, feesum);
        }

        // this frament of code adds new holders, this data needed for future rewards calculations 
        if(!holderIs(to) && !excludeFromHolders[to]) {
            isHolder[to] = true;
            holdersIndex[holdersCount] = to;
            holdersCount++;
        }

        // this frament of code returns donations of expired wishes to personal balances (the number of returns per transaction is determined by the variable numberDonatorsReturnTx)
        uint256 currentReturnsNumber = 0;
        for (uint256 i = 0; i < wishesCount; i++) {
            if(!wishes[i].claimed && isWishExpired(i) && currentReturnsNumber < numberDonatorsReturnTx) {
                for (uint256 j = 0; j < wishes[i].donatorsCount; j++) {
                    address donatorAddress = wishDonatorIndex[i][j];
                    if(!isWishDonatorAmountReturned[i][donatorAddress]) {
                        users[donatorAddress].personalBalance += wishDonatorAmount[i][donatorAddress];
                        isWishDonatorAmountReturned[i][donatorAddress] = true;
                        currentReturnsNumber++;
                    }
                    
                }
            }
        }
    }

    // this function checks whether the wallet is the holder 
    function holderIs(address wallet) public view returns (bool) {
        return isHolder[wallet] && !excludeFromHolders[wallet];
    }

    // this function transfers personal balance to the wallet balance
    function claimPersonalBalance() external onlyMembers notBanned {
        require(users[_msgSender()].personalBalance > 0, "You don't have Personal Balance");
        uint256 amount = users[_msgSender()].personalBalance;
        users[_msgSender()].personalBalance = 0;
        _balances[wishesWallet] -= amount; 
        _balances[_msgSender()] += amount;
        emit Transfer(wishesWallet, _msgSender(), amount);
    }
   
    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        require(tokenAmount > 0, "amount must be greeter than 0");
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function sendETHToFee(uint256 amount) private {
        require(amount > 0, "amount must be greeter than 0");
        TreasuryWallet.transfer(amount);
    }

    function enableTrading() external onlyOwner() {
        require(!tradeEnable,"trading is already open");
        _SwapBackEnable = true;
        tradeEnable = true;
        emit TradingOpenUpdated();
    }  
  
    function excludeFromFee(address account) external onlyOwner {
        require(_isExcludedFromFee[account] != true,"Account is already excluded");
        _isExcludedFromFee[account] = true;
        emit ExcludeFromFeeUpdated(account);
    }
   
    function includeFromFee(address account) external onlyOwner {
        require(_isExcludedFromFee[account] != false, "Account is already included");
        _isExcludedFromFee[account] = false;
        emit includeFromFeeUpdated(account);
    }
   
    function SetTreasuryWallet(address payable _newWallet) external onlyOwner {
        require(_newWallet != address(this), "CA will not be the Fee Reciever");
        require(_newWallet != address(0), "0 addy will not be the fee Reciever");
        TreasuryWallet = _newWallet;
        _isExcludedFromFee[_newWallet] = true;
        emit FeesRecieverUpdated(_newWallet);
    }
    
    function setThreshouldToken(uint256 minToken, uint256 maxToken) external onlyOwner {
        require(maxToken <= (totalSupply() / 100), "amount must be less than or equal to 1% of the supply");
        require(minToken <= (totalSupply() / 333), "amount must be less than or equal to 0.3% of the supply");
        _minSwapTokens = minToken * 10**_decimals;
        _maxSwapTokens = maxToken * 10**_decimals;
        emit SwapThreshouldUpdated(minToken, maxToken);
    }

    function setSwapBackSetting(bool state) external onlyOwner {
        _SwapBackEnable = state;
        emit SwapBackSettingUpdated(state);
    }

    receive() external payable {}
   
    function recoverBEP20FromContract(address _tokenAddy, uint256 _amount) external onlyOwner {
        require(_tokenAddy != address(this), "Owner can't claim contract's balance of its own tokens");
        require(_amount > 0, "Amount should be greater than zero");
        require(_amount <= IERC20(_tokenAddy).balanceOf(address(this)), "Insufficient Amount");
        IERC20(_tokenAddy).transfer(TreasuryWallet, _amount);
        emit ERC20TokensRecovered(_amount); 
    }
 
    function recoverBNBfromContract() external onlyOwner {
        uint256 contractETHBalance = address(this).balance;
        require(contractETHBalance > 0, "Amount should be greater than zero");
        require(contractETHBalance <= address(this).balance, "Insufficient Amount");
        payable(address(TreasuryWallet)).transfer(contractETHBalance);
        emit ETHBalanceRecovered();
    }

    // this function returns sum of tokens of all holders
    function countHoldersAmounts() public view returns(uint256){
        uint256 total = 0;
        for (uint256 i = 0; i < holdersCount; i++) {
            if(holderIs(holdersIndex[i])){
                total += _balances[holdersIndex[i]];
            }
        }
        return total;
    }

    // this function enables premium on 30 days
    function payPremium() external onlyMembers notBanned {
        uint256 pp = premiumPrice * 10**_decimals;
        require(checkAllowanceBalance(pp) && !isPremium(_msgSender()), "(allowance,balances) err or already have premium");
        sendTaxes(_msgSender(), address(0), pp);
        users[_msgSender()].premiumTime = block.timestamp + 2592000; //seconds in 30 days
        _approve(_msgSender(), address(this), allowance(_msgSender(), address(this)) - pp);
        emit PremiumPaid(_msgSender());
    }

    function isPremium(address account) public view returns(bool) {
        return users[account].premiumTime > block.timestamp;
    }

    // this function changes distribution wallets
    function setDistribution(address[] calldata newWallets, uint256[] calldata newPerentages) external onlyOwner {
        require(newWallets.length == newPerentages.length, "22");

        uint256 sum = 0;
        bool error = false;

        for (uint256 i = 0; i < newPerentages.length; i++) {
            sum += newPerentages[i];
            if(newWallets[i] == mlmWallet) {
                error = true;
                break;
            }
        }
        
        require(!error && sum < 100, "13"); 

        for (uint256 j = 0; j < distributionCount; j++) {
            if(distributionIndex[j] != mlmWallet) {
                _isExcludedFromFee[distributionIndex[j]] = false;
                excludeFromHolders[distributionIndex[j]] = false;
            }
        }

        for (uint256 k = 0; k < newWallets.length; k++) {
            distribution[k] = newPerentages[k];
            distributionIndex[k] = newWallets[k];
            _isExcludedFromFee[newWallets[k]] = true;
            excludeFromHolders[newWallets[k]] = true;
        }

        uint256 count = newWallets.length + 1;
        distributionCount = count;
        uint256 mlmIndex = count - 1;
        distribution[mlmIndex] = 100 - sum;
        distributionIndex[mlmIndex] = mlmWallet;
    }

    // this function creating new member
    function register(string calldata ava, string calldata uname, address referrer) external notBanned {
        require(!isMember(_msgSender()) && isMember(referrer) && _msgSender() != referrer && !banSnipers[referrer] && !uniqueUnames[uname], "12");
        users[_msgSender()] = User(block.timestamp, ava, uname, referrer, 0, 0, block.timestamp, 0, 0, 0, 0);
        uniqueUnames[uname] = true;
        usersIndex[totalMembers] = _msgSender();
        referrals[referrer][users[referrer].referralCount] = _msgSender();
        users[referrer].referralCount++;
        totalMembers++;
        emit Registration(_msgSender(), referrer);
    }

    // this function can update member's ava and username
    function updateProfile(string calldata ava, string calldata uname) external onlyMembers notBanned {
        require(!uniqueUnames[uname], "9");
        uniqueUnames[users[_msgSender()].uname] = false;
        users[_msgSender()].uname = uname;
        users[_msgSender()].ava = ava;
        uniqueUnames[uname] = true;
    }

    // this functions calculates and accrues referral rewards
    function addBonus(address from, address to, uint256 amount) internal {
        address currentMember = from == wishesWallet || from == mlmWallet ? to : from;
        for (uint256 i = 0; i < 7; i++) {
            if (users[currentMember].referrer == address(0)) {
                break;
            }

            uint256 bonus = (amount * (80 - i * 10)) / 350;

            referralsAmounts[from][users[currentMember].referrer] += bonus;
            if(i < 3){
                users[users[currentMember].referrer].payoutAmountSimple += bonus;
            } else {
                users[users[currentMember].referrer].payoutAmountPremium += bonus;
            }

            currentMember = users[currentMember].referrer;
        }
    }

    function getReferralAmount(address from, address referrer) public view onlyPremium returns(uint256) {
        return referralsAmounts[from][referrer];
    }

    // this function transfers referral rewards to member's wallet
    function claimBonus() external onlyMembers notBanned {
        uint256 bA = bonusAmount(_msgSender());
        require(bA > 0, "You have no bonus");
        
        users[_msgSender()].payoutAmountSimple = 0;
        if (isPremium(_msgSender())) {
            users[_msgSender()].payoutAmountPremium = 0;
        }

        _transfer(mlmWallet, _msgSender(), bA);
        emit Payout(_msgSender(), bA);
    }

    function bonusAmount(address addr) public view returns (uint256) {
        return isPremium(addr) ? (users[addr].payoutAmountSimple + users[addr].payoutAmountPremium) : users[addr].payoutAmountSimple;
    }

    function changeCreateWishPrice(uint256 newPrice) external onlyOwner {
        createWishPrice = newPrice;
    }

    // this function changes the number of seconds during which a wish can accept donations
    function changeWishesClaimPeriod(uint256 newPeriod) external onlyOwner {
        wishesClaimPeriod = newPeriod;
    }

    function changeTaxes(uint256 buy, uint256 sell) external onlyOwner {
        require(buy <= 10 && sell <= 10, "!>10");
        buyTaxes = buy;
        sellTaxes = sell;
        emit TaxesChanged(buy, sell);
    }

    // this functions transfers wishes donations to wish owner wallet 
    function claimWish(uint256 wishID) external onlyMembers notBanned {
        require(!wishes[wishID].claimed && wishes[wishID].owner == _msgSender() && wishes[wishID].amount >= wishes[wishID].tAmount && !isWishExpired(wishID), "Wish is expired");
        wishes[wishID].claimed = true;
        _transfer(wishesWallet, _msgSender(), wishes[wishID].amount);
        emit wishClaimed(wishID, wishes[wishID].amount, block.timestamp);
    }

    function isWishExpired(uint256 wishID) public view returns (bool) {
        return (wishes[wishID].time + wishesClaimPeriod) <= block.timestamp;
    }

    function checkAllowanceBalance(uint256 a) public view returns (bool){
        return _allowances[_msgSender()][address(this)] >= a && balanceOf(_msgSender()) >= a;
    }

    // this functions credits donations to the wish balance and stores statistics of donations
    function donate(uint256 wishID, uint256 a, bool personalBalance) external onlyMembers notBanned {
        require(!isWishExpired(wishID) && !wishes[wishID].claimed, "Wish is expired");

        if (personalBalance) {
            require(users[_msgSender()].personalBalance >= a, "Not enough tokens on personal balance");
            users[_msgSender()].personalBalance -= a;
        } else {
            require(checkAllowanceBalance(a), "Check allowance or balance");
            _transfer(_msgSender(), wishesWallet, a);
            _approve(_msgSender(), address(this), _allowances[_msgSender()][address(this)] - a);
        }
        
        wishDonatorAmount[wishID][_msgSender()] = personalBalance ? a : (a - (a * buyTaxes / 100));
        wishes[wishID].amount += wishDonatorAmount[wishID][_msgSender()];
        if(!isDonator(_msgSender())){
            donatorsIndex[donatorsCount] = _msgSender();
            donatorsCount++;
        }
        users[_msgSender()].donatesAmount += wishDonatorAmount[wishID][_msgSender()];
        totalDonatesAmountCurrent += wishDonatorAmount[wishID][_msgSender()];
        if(!isWishDonator[wishID][_msgSender()]){
            isWishDonator[wishID][_msgSender()] = true;
            wishDonatorIndex[wishID][wishes[wishID].donatorsCount] = _msgSender();
            wishes[wishID].donatorsCount += 1;
        }
     
        emit NewDonate(_msgSender(), a, wishID);
    }

    function isDonator(address wallet) public view returns (bool) {
        return (users[wallet].donatesAmount + users[wallet].oldDonatesAmount) > 0;
    }

    function isMember(address wallet) public view returns (bool) {
        return users[wallet].time > 0;
    }

    function resetDonators() external onlyOwner {
        for(uint256 i = 0; i < donatorsCount; i++){
            users[donatorsIndex[i]].oldDonatesAmount += users[donatorsIndex[i]].donatesAmount;
            users[donatorsIndex[i]].donatesAmount = 0;
        }
        donatorsCount = 0;
        totalDonatesAmount += totalDonatesAmountCurrent;
        totalDonatesAmountCurrent = 0;
    }

    function getHolders(uint256 startIndex, uint256 endIndex) public view returns(address[] memory, uint256[] memory) {
        require(startIndex < endIndex && endIndex <= holdersCount, "19");
        uint256 arrLength = 0;
        for(uint256 i = startIndex; i < endIndex; i++){
            if(holderIs(holdersIndex[i])){
                arrLength++;
            }
        }
        address[] memory wallets = new address[](arrLength);
        uint256[] memory balances = new uint256[](arrLength);
        arrLength = 0;
        for(uint256 i = startIndex; i < endIndex; i++){
            if(holderIs(holdersIndex[i])){
                wallets[arrLength] = holdersIndex[i];
                balances[arrLength] = balanceOf(holdersIndex[i]);
                arrLength++;
            }
        }
        return (wallets, balances);
    }

    function getMembers(uint256 startIndex, uint256 endIndex) public view returns(User[] memory) {
        require(startIndex < endIndex && endIndex <= totalMembers, "19");
        User[] memory arr = new User[](endIndex - startIndex);
        for(uint256 i = startIndex; i < endIndex; i++){
            arr[i] = users[usersIndex[i]];
        }
        return arr;
    }

    function getDonators(uint256 startIndex, uint256 endIndex) public view returns(User[] memory) {
        require(startIndex < endIndex && endIndex <= donatorsCount, "19");
        User[] memory arr = new User[](endIndex - startIndex);
        for(uint256 i = startIndex; i < endIndex; i++){
            arr[i] = users[donatorsIndex[i]];
        }
        return arr;
    }

    // this functions creates new wish
    function createWish(uint256 totalAmount) external onlyMembers notBanned {
        uint256 price = createWishPrice * (10 ** _decimals);
        require(checkAllowanceBalance(price), "Check allowance or balance");
        sendTaxes(_msgSender(), address(0), price);
        wishes[wishesCount] = Wish(block.timestamp, 0, totalAmount * (10 ** _decimals), false, 0, _msgSender());
        _approve(_msgSender(), address(this), allowance(_msgSender(), address(this)) - price);
        emit wishCreated(wishesCount, wishes[wishesCount].tAmount);
        wishesCount++;
    }

    function getPair() public view onlyOwner returns(address){
        return uniswapV2Pair;
    }

    function changeNumberDonatorsReturnTx(uint256 newNumber) external onlyOwner {
        numberDonatorsReturnTx = newNumber;
    }

    function excludeFromHolder(address wallet) external onlyOwner {
        excludeFromHolders[wallet] = true;
    }

    function getMyPersonalBalance() public view returns (uint256) {
        return users[_msgSender()].personalBalance;
    }
}
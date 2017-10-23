pragma solidity 0.4.18;

// Defines the interface used to interact with the token contraact
interface TokenDraft {

    function transfer(address _recipient, uint256 _amount);
}

// implement safemath as a library
library SafeMath {

  function mul(uint256 a, uint256 b) internal constant returns (uint256) {
    uint256 c = a * b;
    require(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal constant returns (uint256) {
    uint256 c = a / b;
    return c;
  }

  function sub(uint256 a, uint256 b) internal constant returns (uint256) {
    require(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal constant returns (uint256) {
    uint256 c = a + b;
    require(c >= a);
    return c;
  }
}

contract Administration {

    // contract creator
    address     public owner;
    
    // adminitrators
    mapping (address => bool) public moderators;

    event AddMod(address indexed _invoker, address indexed _newMod, bool indexed _modAdded);
    event RemoveMod(address indexed _invoker, address indexed _removeMod, bool indexed _modRemoved);

    function Administration() {
        owner = msg.sender;
    }

    /// @notice User must be owner or mod
    modifier onlyAdmin() {
        require(msg.sender == owner || moderators[msg.sender] == true);
        _;
    }

    /// @notice User must be owner
    modifier onlyOwner() {
        require(msg.sender == owner);
        _; // function code inserted here
    }

    /// @notice Change the owner
    function transferOwnership(address _newOwner) public onlyOwner returns (bool success) {
        owner = _newOwner;
        return true;
        
    }

    /// @notice Add a moderator
    function addModerator(address _newMod) public onlyOwner returns (bool added) {
        require(_newMod != address(0x0));
        moderators[_newMod] = true;
        AddMod(msg.sender, _newMod, true);
        return true;
    }
    
    /// @notice Remove a moderator
    function removeModerator(address _removeMod) public onlyOwner returns (bool removed) {
        require(_removeMod != address(0x0));
        moderators[_removeMod] = false;
        RemoveMod(msg.sender, _removeMod, true);
        return true;
    }

}

contract Presale is Administration {
    // Use safemath for uint256
    using SafeMath for uint256;

    address[] public backers; // stores a list of backers
    address public  hotWallet; // hotwallet which will store ether raised
    address public  tokenContractAddress; // address of the token contract
    uint256 public  earlyBirdReserve; // number of tokens available in sale
    uint256 public  tokenCostInWei; // price of token in wei
    uint256 public  minContributionAmount; // minimum contribution amount
    uint256 public  tokenSold; // number of tokens sold 
    uint256 public  tokensRemaining; // number of tokens left to be sold
    uint256 public  endOfEarlyBird; // will contain the end date, set when launch function invoked
    bool    public  contractLaunched;
    bool    public  earlyBirdClosed;
    bool    public  earlyBirdOver;
    bool    public  withdrawalsEnabled;
    TokenDraft public tokenContract; // token contract handler

    mapping (address => uint256) public balances; // tracks token balances
    mapping (bytes32 => uint256) btcBalances; // tracks token balances for users contributing via btc
    mapping (address => uint256) public ethBalances; // tracks eth balances in case of refunds

    event LaunchContract(address indexed _launcher, bool indexed _launched);
    event ResumeSale(address indexed _invoker, bool indexed _resumed);
    event PauseSale(address indexed _invoker, bool indexed _paused);
    event LogContribution(address indexed _backer, uint256 _fanReceived, uint256 _ethSent, bool indexed _contributed);
    event LogBtcContribution(uint256 _amountFAN, bool _contributed);
    event TokenTransfer(address indexed _sender, address indexed _recipient, uint256 _amount);
    event EthRefund(address indexed _backer, uint256 _ethAmount, bool indexed _ethRefunded);
    event PriceUpdate(address indexed _invoker, uint256  _newPrice, bool indexed _priceChanged);

    /// @notice Only usable before the launch contract function is ran
    modifier preLaunch() {
        require(!contractLaunched);
        _;
    }

    /// @notice Only usable after the launch contract function is ran
    modifier postLaunch() {
        require(contractLaunched);
        _;
    }

    /// @notice Requires that withdrawals are enabled
    modifier withdrawalEnabled() {
        require(withdrawalsEnabled);
        _;
    }

    /// @notice Deploy the contract 
    function Presale(address _tokenContractAddress, address _hotWallet) {
        tokenContract = TokenDraft(_tokenContractAddress);
        tokenContractAddress = _tokenContractAddress;
        hotWallet = _hotWallet;
        contractLaunched = false;
        earlyBirdClosed = true;
        tokenSold = 0;
        earlyBirdReserve = 75000000000000000000000000; 
        tokensRemaining = 75000000000000000000000000;
        tokenCostInWei = 500000000000000;            
        minContributionAmount = 100000000000000000000000;
    }

    /// @notice Fallback function ,executed when contract receives ether
    function() payable {
        require(!earlyBirdOver);
        if (now > endOfEarlyBird) { // check to see if current time is past deadline
            earlyBirdOver = true; // if so set to sale to over
        }
        require(contractLaunched);
        require(!earlyBirdClosed);
        require(contribute(msg.sender));
    }

    /// @notice Used to log a contribution made via btc, only usable by owner or moderator
    /// @param _email The email address of the backer, must be unique, used to identify backers
    /// @param _amountFAN The number of FAN tokens in wei to allocate 
    function logBtcContribution(string _email, uint256 _amountFAN)
        public
        onlyAdmin
        returns (bool _btcContributionLogged)
    {
        require(_amountFAN > 0); // check that value passed in is greater than 0
        require(tokensRemaining > 0); // ensure there are enough tokens left
        require(_amountFAN <= tokensRemaining); // ensure that the amount is <= to total supply
        bytes32 email = keccak256(_email); // generate checksum of email address
        require(balances[this].sub(_amountFAN) >= 0); 
        require(btcBalances[email].add(_amountFAN) > btcBalances[email]);
        require(btcBalances[email].add(_amountFAN) > 0);
        balances[this] = balances[this].sub(_amountFAN); // deduct balance from contract
        btcBalances[email] = btcBalances[email].add(_amountFAN); // credit backer with balance
        tokenSold = tokenSold.add(_amountFAN); // increase tokens sold
        tokensRemaining = tokensRemaining.sub(_amountFAN); // decrease tokens remaining
        if (tokensRemaining == 0) { // if tokens remaining is 0
            earlyBirdOver = true; // set sale to over
            earlyBirdClosed = true; // set sale to closed
        }
        LogBtcContribution(_amountFAN, true); // log contribution
        return true;
    }

    /// @notice Used to update the price in case of wild ether fluctuations, invoker must be admin
    /// @param _newTokenCostInWei New price of the token in units of wei
    function updateTokenCost(uint256 _newTokenCostInWei)
        public
        onlyAdmin
        returns (bool _priceChanged)
    {
        require(_newTokenCostInWei > 0); // require value is greater than 0
        tokenCostInWei = _newTokenCostInWei; 
        PriceUpdate(msg.sender, _newTokenCostInWei, true); // notify blockchain of update
        return true;
    }

    /// @notice Used to resume crowdsale if it is ever paused
    function resumeEarlyBird()
        public
        onlyAdmin
        postLaunch
        returns (bool resumed)
    {
        require(earlyBirdClosed);
        earlyBirdClosed = false;
        ResumeSale(msg.sender, true);
        return true;
    }

    /// @notice Used to pause the presale if trouble arises
    function pauseEarlyBird()
        public
        onlyAdmin
        postLaunch
        returns (bool paused)
    {
        require(!earlyBirdClosed);
        earlyBirdClosed = true;
        PauseSale(msg.sender, true);
        return true;
    }

    /// @notice Used to launch contract, activate sale, set end date.
    /// @notice SEND THE TOKENS BEFORE LAUNCHING THE CONTRACT
    function launchContract()
        public
        onlyAdmin
        preLaunch
        returns (bool launched)
    {
        endOfEarlyBird = now + 10 days; // set end date of the sale to 10 days from now
        contractLaunched = true; // set contract as launched
        earlyBirdClosed = false; // set early bird as open
        earlyBirdOver = false; // set early bird as open
        balances[this] = earlyBirdReserve; // credit contract with token balance
        LaunchContract(msg.sender, true); // notify blockchain of launch event
        return true;
    }

    /// @notice Used to enable withdrawals
    function enableWithdrawals()
        public
        onlyAdmin
        returns (bool _enabled)
    {
        withdrawalsEnabled = true;
        return true;
    }

    /// @notice Used to broadcast/push withdrawals to backers
    /// @param _backer The ETH address of the backer
    function broadcastWithdrawal(address _backer)
        public
        onlyAdmin
        withdrawalEnabled
        returns (bool _withdrawn)
    {
        require(balances[_backer] > 0); // checks that backer has a balance greater than 0
        uint256 _rewardAmount = balances[_backer]; // set reward amount
        balances[_backer] = 0; // empty balance, preventing reentrancy
        tokenContract.transfer(_backer, _rewardAmount); // transfer tokens to backer
        TokenTransfer(this, msg.sender, _rewardAmount); // notify blockchain of token transfer
        return true;
    }

    /// @notice Used to broadcast withdrawals to people who contributed with BTC
    /// @param _email The emaiil address to identify the backer
    /// @param _destinationAddress The ETH address of the backer to send tokens to
    function broadcastBtcWithdrawal(string _email, address _destinationAddress)
        public
        onlyAdmin
        withdrawalEnabled
        returns (bool _withdrawn)
    {
        bytes32 email = keccak256(_email); // generate checksum of email
        require(btcBalances[email] > 0); // check that the balance for checksum is greater than 0
        uint256 _rewardAmount = btcBalances[email]; // set reward amount
        btcBalances[email] = 0; // empty balance to prevent reentrancy
        tokenContract.transfer(_destinationAddress, _rewardAmount); // transfer tokens
        TokenTransfer(this, _destinationAddress, _rewardAmount); // notify blockchain of token transfer
        return true;
    }

    /// @notice Used by a contribute to withdraw fan tokens
    function withdrawFAN()
        public
        withdrawalEnabled
        returns (bool _withdrawn)
    {
        require(balances[msg.sender] > 0); // Check that sender has a balance greater than 0
        uint256 _rewardAmount = balances[msg.sender]; // set reward amount
        balances[msg.sender] = 0; // Empty balance to prevent reentrancy
        tokenContract.transfer(msg.sender, _rewardAmount); // Send tokens to backer
        TokenTransfer(this, msg.sender, _rewardAmount); // Notify blockchain of transfer
        return true;
    }

    /// @notice Used by a backer to withdraw ETH in case they tried to buy more tokens
    /// than the remaining supply
    function withdrawETH()
        public
        returns (bool _withdrawn)
    {
        require(ethBalances[msg.sender] >= 0); // Check that they have a balance greater than 0
        uint256 _ethAmount = ethBalances[msg.sender]; // Set eth amount
        ethBalances[msg.sender] = 0; // empty balance to prevent reentrancy
        msg.sender.transfer(_ethAmount); // Send the ether to backer
        EthRefund(msg.sender, _ethAmount, true); // notify blockchain of ether refund
        return true;
    }

    /// @notice Used to contribute ether
    /// @param _backer Backer address
    function contribute(address _backer)
        public
        payable
        returns (bool contributed)
    {
        require(msg.sender == _backer); // requires that the _backer param is set to msg.sender
        require(tokensRemaining > 0); // require tokens remaining greater than 0
        require(_backer != address(0x0)); // ensure address isn't empty
        uint256 _amountFAN = msg.value / tokenCostInWei; // calculate token cost
        uint256 amountFAN = _amountFAN.mul(1 ether); // calculate token cost
        require(amountFAN >= minContributionAmount); // check to see if greater than supply
        uint256 amountCharged;
        uint256 amountRefund;
        if (amountFAN >= tokensRemaining) { // if greater than supply
            amountFAN = tokensRemaining; // set reward amount to remaining supply
            uint256 _amountCharged = amountFAN.mul(tokenCostInWei); // calculate charged amount
            amountCharged = _amountCharged.div(1 ether); // calculate charged amount
            amountRefund = msg.value.sub(amountCharged); // calculate refund amount
            earlyBirdOver = true; // set sale as over
            earlyBirdClosed = true; // set sale os closed
        }
        if (amountRefund > 0) { // check to see if they get refund
            ethBalances[_backer] = ethBalances[_backer].add(amountRefund); // log refund
        } else {
            amountCharged = msg.value;
        }
        balances[this] = balances[this].sub(amountFAN);
        balances[_backer] = balances[_backer].add(amountFAN);
        tokensRemaining = tokensRemaining.sub(amountFAN);
        tokenSold = tokenSold.add(amountFAN);
        backers.push(_backer);
        hotWallet.transfer(amountCharged);
        LogContribution(_backer, amountFAN, amountCharged, true);
        return true;
    }

    //GETTERS/

    function getTokenSold()
        public
        constant
        returns (uint256 _tokenSold)
    {
        return tokenSold;
    }

    function getRemainingTokens()
        public
        constant
        returns (uint256 _remainingTokens)
    {
        return tokensRemaining;
    }

    function getBtcContribution(string _email)
        public
        constant
        returns (uint256 _btcBalance)
    {
        bytes32 email = keccak256(_email);
        return btcBalances[email];
    }
}
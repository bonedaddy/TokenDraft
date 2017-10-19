pragma solidity 0.4.17;

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

// Used for function invoke restriction
contract Administration {

    address     public owner; // temporary address
    
    mapping (address => bool) public moderators;

    event AddMod(address indexed _invoker, address indexed _newMod, bool indexed _modAdded);
    event RemoveMod(address indexed _invoker, address indexed _removeMod, bool indexed _modRemoved);

    function Administration() {
        owner = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner || moderators[msg.sender] == true);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _; // function code inserted here
    }

    function transferOwnership(address _newOwner) onlyOwner returns (bool success) {
        owner = _newOwner;
        return true;
        
    }

    function addModerator(address _newMod) onlyOwner returns (bool added) {
        require(_newMod != address(0x0));
        moderators[_newMod] = true;
        AddMod(msg.sender, _newMod, true);
        return true;
    }
    
    function removeModerator(address _removeMod) onlyOwner returns (bool removed) {
        require(_removeMod != address(0x0));
        moderators[_removeMod] = false;
        RemoveMod(msg.sender, _removeMod, true);
        return true;
    }

}

contract EarlyBird is Administration {
    using SafeMath for uint256;

    address public  hotWallet;
    address public  tokenContractAddress;
    uint256 public  earlyBirdReserve;
    uint256 public  tokenCostInWei;
    uint256 public  minContributionAmount;
    uint256 public  tokenSold;
    uint256 public  tokensRemaining;
    uint256 public  endOfEarlyBird;
    bool    public  contractLaunched;
    bool    public  earlyBirdClosed;
    bool    public  earlyBirdOver;
    bool    public  withdrawalsEnabled;
    TokenDraft public tokenContract;

    mapping (address => uint256) public balances;
    mapping (address => uint256) public ethBalances;

    event LaunchContract(address indexed _launcher, bool indexed _launched);
    event ResumeSale(address indexed _invoker, bool indexed _resumed);
    event PauseSale(address indexed _invoker, bool indexed _paused);
    event LogContribution(address indexed _backer, uint256 _fanReceived, uint256 _ethSent, bool indexed _contributed);
    event TokenTransfer(address indexed _sender, address indexed _recipient, uint256 _amount);

    modifier preLaunch() {
        require(!contractLaunched);
        _;
    }

    modifier postLaunch() {
        require(contractLaunched);
        _;
    }

    modifier withdrawalEnabled() {
        require(withdrawalsEnabled);
        _;
    }

    function EarlyBird(address _tokenContractAddress, address _hotWallet) {
        tokenContract = TokenDraft(_tokenContractAddress);
        hotWallet = _hotWallet;
        contractLaunched = false;
        earlyBirdClosed = true;
        tokenSold = 0;
        earlyBirdReserve = 178571430000000000000000;  // 178571.43 in wei
        tokensRemaining = earlyBirdReserve;
        tokenCostInWei = 400000000000000;             // $0.14 in wei
        minContributionAmount = 81250000000000000000; // $25,000 in wei
    }

    function() payable {
        if (now > endOfEarlyBird) {
            earlyBirdOver = true;
        }
        require(!earlyBirdOver);
        require(contractLaunched);
        require(!earlyBirdClosed);
        contribute(msg.sender, msg.value);
    }

    /// @notice Used to pause the presale if trouble arises
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

    /// @notice Used to launch contract, send tokens before invoking
    function launchContract()
        public
        onlyAdmin
        preLaunch
        returns (bool launched)
    {
        endOfEarlyBird = now + 10 days;
        contractLaunched = true;
        earlyBirdClosed = false;
        earlyBirdOver = false;
        balances[this] = earlyBirdReserve;
        LaunchContract(msg.sender, true);
        return true;
    }

    function enableWithdrawals()
        public
        onlyAdmin
        returns (bool _enabled)
    {
        withdrawalsEnabled = true;
        return true;
    }

    function broadcastWithdrawal(address _backer)
        public
        onlyAdmin
        withdrawalEnabled
        returns (bool _withdrawn)
    {
        require(balances[_backer] > 0);
        uint256 _rewardAmount = balances[_backer];
        balances[_backer] = 0;
        tokenContract.transfer(_backer, _rewardAmount);
        TokenTransfer(this, msg.sender, _rewardAmount);
        return true;
    }

    function withdrawFAN()
        public
        withdrawalEnabled
        returns (bool _withdrawn)
    {
        require(balances[msg.sender] > 0);
        uint256 _rewardAmount = balances[msg.sender];
        balances[msg.sender] = 0;
        tokenContract.transfer(msg.sender, _rewardAmount);
        TokenTransfer(this, msg.sender, _rewardAmount);
        return true;
    }

    function contributionCheck(address _backer, uint256 _msgValue)
        private
        constant
        returns (bool valid)
    {
        require(_backer != address(0x0));
        require(_msgValue >= minContributionAmount);
        require(tokensRemaining > 0);
        return true;
    }

    function contribute(address _backer, uint256 _msgValue)
        payable
        returns (bool contributed)
    {
        require(contributionCheck(_backer, _msgValue));
        uint256 _amountFAN = _msgValue.div(tokenCostInWei);
        uint256 amountFAN = _amountFAN.mul(1 ether);
        uint256 amountCharged;
        uint256 amountRefund;
        if (amountFAN >= tokensRemaining) {
            amountFAN = tokensRemaining;
            uint256 _amountCharged = _amountFAN.mul(tokenCostInWei);
            amountCharged = _amountCharged.div(1 ether);
            amountRefund = _msgValue.sub(amountCharged);
        }
        if (amountRefund > 0) {
            ethBalances[_backer] = ethBalances[_backer].add(amountRefund);
        } else {
            amountCharged = msg.value;
        }
        balances[this] = balances[this].sub(amountFAN);
        balances[_backer] = balances[_backer].add(amountFAN);
        tokensRemaining = tokensRemaining.sub(amountFAN);
        tokenSold = tokenSold.add(amountFAN);
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
}
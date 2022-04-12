// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract AGGSmartEvents {
    address payable DevWallet;
    bool locked;
    
    mapping(address => bool) approvedAddresses;

    enum EventState{
        SignUp, // event is in sigup state
        Active, // event is in on-going state
        AwaitingLeaderboard, // event is ended. it's awaiting leaderboard positions.
        AwaitingConfirms, // positions are submitted. top players can vote to confirm the positions.
        AwaitingAdminValidation, // players voted... an admin must validate to start delivering the rewards.
        Withdrawable, // it passed all validations. top players can withdraw their rewards.
        Disproved, // Not confirmed by top players of this event (scores not confirmed in the time limit)
        Invalidated // event admin invalidated this event for some reasons.
    }

    struct Player {
        uint tokenID;
        uint position;
        address payable playerAddress;
        bool voted;
        bool withdrawn;
    }

    struct EventType {
        uint typeID;
        string eventTypeTitle;
        address paymentTokenAddress;
        uint paymentTokenAmount;
        uint activeDurationHours;
        uint confirmDurationHours;
        uint entrySize;
        uint confirmationSize;
        uint confirmationHighestAllowedPosition;
        mapping (uint => RewardDistributionRule) RewardDistributionRules;
        uint RewardDistributionRulesCount;
    }

    struct AGGEvent { // AaveGotchi.Games Events structure
        mapping (uint => Player) players;
        uint playersSize;
        uint eventTypeID;
        EventState state;
        address validator;
        bool isBusy;
    }

    struct RewardDistributionRule {
        uint fromPos;
        uint toPos;
        uint AmountEachPos;
    }

    modifier onlyDev() {
        require(msg.sender == DevWallet, "Not Dev!");
        _;
    }

    modifier validAddress(address _addr) {
        require(_addr != address(0), "Not valid address!");
        _;
    }

    modifier lockUP() {
        require(!locked, "No ReEnterancy!");

        locked = true;
        _;
        locked = false;
    }

    modifier lockUpEvent(uint eventID) {
        require(!events[eventID].isBusy || events[eventID].state == EventState.Active, "Someone is signing up for that specific event at the same time! to prevent conflicts, We need you to try again later...");
        events[eventID].isBusy = true;
        _;
        events[eventID].isBusy = false;
    }

    function changeDev(address _newDevWallet) public onlyDev validAddress(_newDevWallet) {
        DevWallet = payable(_newDevWallet);
    }

    constructor() {
        DevWallet = payable(msg.sender);
    }

    uint256 lastEventID;

    EventType[] internal eventTypes;
    AGGEvent[] internal events;

    function defineNewEventType(string memory title, address paymentTokenAddress, uint tokenAmount, uint durationHours, uint confirmationHours, uint entrySize, uint confimationSize, uint confrimationHighestPosition, uint[3][] memory RewardDistributionRules) onlyDev lockUP public {
        uint newIndex = eventTypes.length;
        eventTypes.push();

        require(RewardDistributionRules.length > 0, "Please define the Reward distribution rules!");

        EventType storage tmpEventType = eventTypes[newIndex];

        tmpEventType.typeID = newIndex;
        tmpEventType.eventTypeTitle = title;
        tmpEventType.paymentTokenAddress = paymentTokenAddress;
        tmpEventType.paymentTokenAmount = tokenAmount;
        tmpEventType.activeDurationHours = durationHours;
        tmpEventType.confirmDurationHours = confirmationHours;
        tmpEventType.entrySize = entrySize;
        tmpEventType.confirmationSize = confimationSize;
        tmpEventType.confirmationHighestAllowedPosition = confrimationHighestPosition;

        for (uint i = 0; i < RewardDistributionRules.length; i++) {
            require(RewardDistributionRules[i].length > 2, "Please define the Reward distribution rules correctly!");
            tmpEventType.RewardDistributionRules[i] = RewardDistributionRule(RewardDistributionRules[i][0], RewardDistributionRules[i][1], RewardDistributionRules[i][2]);
            tmpEventType.RewardDistributionRulesCount++;
        }

    }

 
    function getEventData(uint eventID) public view returns(string[] memory) {
    require(eventID >= 0 && eventID < events.length, "No such event!");
    string[] memory output = new string[](events.length);

    for (uint i = 0; i < events.length; i++) {
        output[i] = string(abi.encodePacked("[", events[eventID].players[i].tokenID, ",", events[eventID].players[i].position, ",", events[eventID].players[i].playerAddress, ",", events[eventID].players[i].voted, "]"));
    }

    return output;
    }

    function getEventTypesCount() public view returns(uint) {
        return eventTypes.length;
    }

    function signUp(uint eventTypeID, uint tokenID) payable lockUpEvent(lastEventID) public {
        require(eventTypeID >= 0 && eventTypeID < eventTypes.length, "No such eventType!");

        IERC20 paymentToken = IERC20(eventTypes[eventTypeID].paymentTokenAddress);
        uint256 amountToPay = eventTypes[eventTypeID].paymentTokenAmount;
        
        if (paymentToken.allowance(msg.sender, address(this))  >= amountToPay) {
            approvedAddresses[msg.sender] = true;
        } else {
            approvedAddresses[msg.sender] = false;
        }

        require(paymentToken.allowance(msg.sender, address(this))  >= amountToPay, "Not approved for that amount!");
        require(paymentToken.transferFrom(msg.sender, address(this), amountToPay),"Transfer Failed!");
       
        Player memory tmpPlayer;

        tmpPlayer.tokenID = tokenID;
        tmpPlayer.position = 0;
        tmpPlayer.playerAddress = payable(msg.sender);
        tmpPlayer.voted = false;
        tmpPlayer.withdrawn = false;

        if (lastEventID >= events.length) {
            lastEventID = events.length;
            events.push();
            events[lastEventID].eventTypeID = eventTypeID;
        }

        require(events[lastEventID].state == EventState.SignUp, "This event is not open for new signups! try again for a new one...");
        require(events[lastEventID].players[tokenID].playerAddress != address(0), "This Gotchi is already registered in this event!");

        events[lastEventID].players[tokenID] = tmpPlayer;
        events[lastEventID].playersSize++;
  
        if (eventTypes[eventTypeID].entrySize == events[lastEventID].playersSize) {
            events[lastEventID].state = EventState.Active;
            lastEventID++; // new event will be created for the next signup if this(lastEventID's) event is not created yet...
        }
    }
}
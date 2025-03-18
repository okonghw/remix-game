#pragma version 0.4.0
# Fortune Cookie Smart Contract
# Allows users to get random fortunes for a small fee
# Users can submit fortunes and get a refund when they do
# Users can view their fortune history
# Users can vote (thumbs up/down) on fortunes (one vote per fortune per wallet)

# Event logs
event FortuneReceived:
    recipient: indexed(address)
    fortune: String[200]
    fortuneId: uint256
    timestamp: uint256

event FortuneSubmitted:
    submitter: indexed(address)
    fortune: String[200]
    fortuneId: uint256
    timestamp: uint256

event FortuneRejected:
    submitter: indexed(address)
    fortune: String[200]
    timestamp: uint256

event FortuneVoted:
    voter: indexed(address)
    fortuneId: uint256
    isUpvote: bool
    timestamp: uint256

event VoteRemoved:
    voter: indexed(address)
    fortuneId: uint256
    timestamp: uint256

event OwnershipTransferred:
    previousOwner: indexed(address)
    newOwner: indexed(address)

# Vote type enum
VOTE_NONE: constant(int128) = 0
VOTE_UP: constant(int128) = 1
VOTE_DOWN: constant(int128) = 2

# State variables
owner: public(address)
fortunePrice: public(uint256)  # Price in wei to get a fortune
fortunes: public(HashMap[uint256, String[200]])  # Fortune ID -> Fortune string
fortuneCount: public(uint256)  # Total number of fortunes
initialFortunesAdded: public(bool)  # Flag to track if initial fortunes were added
MAX_FORTUNE_LENGTH: constant(uint256) = 200  # Maximum fortune length in characters

# User fortune history
userFortuneIds: public(HashMap[address, uint256[100]])  # User -> Array of fortune IDs they've received
userFortuneCount: public(HashMap[address, uint256])  # User -> Count of fortunes received
MAX_USER_FORTUNES: constant(uint256) = 100  # Maximum number of fortunes to track per user

# Voting system
fortuneUpvotes: public(HashMap[uint256, uint256])  # Fortune ID -> Upvote count
fortuneDownvotes: public(HashMap[uint256, uint256])  # Fortune ID -> Downvote count
userVotes: public(HashMap[address, HashMap[uint256, int128]])  # User -> Fortune ID -> Vote type (0=none, 1=up, 2=down)

# Initialize contract
@deploy
def __init__():
    self.owner = msg.sender
    self.fortunePrice = 1000000000000000  # 0.001 ETH in wei
    self.fortuneCount = 0
    self.initialFortunesAdded = False

# Add initial fortunes (only owner, can only be called once)
@external
def addInitialFortunes(initialFortunes: String[200][10]):
    assert msg.sender == self.owner, "Only owner can add initial fortunes"
    assert not self.initialFortunesAdded, "Initial fortunes already added"
    
    # Add each fortune to the collection
    for i in range(10):
        if len(initialFortunes[i]) == 0:
            break  # Stop at first empty fortune
        
        assert len(initialFortunes[i]) <= MAX_FORTUNE_LENGTH, "Fortune too long"
        
        # Add the fortune
        self.fortunes[self.fortuneCount] = initialFortunes[i]
        self.fortuneCount += 1
    
    # Mark initial fortunes as added
    self.initialFortunesAdded = True

# Get a random fortune (costs fortune price)
@payable
@external
def getFortune() -> String[200]:
    # Ensure there are fortunes to give
    assert self.fortuneCount > 0, "No fortunes available"
    
    # Check if correct price was paid
    assert msg.value >= self.fortunePrice, "Insufficient payment"
    
    # Generate a pseudo-random index
    # Note: This is not cryptographically secure, but sufficient for a fortune cookie
    randomSeed: uint256 = convert(
        keccak256(
            concat(
                convert(blockhash(block.number - 1), bytes32),
                convert(block.timestamp, bytes32),
                convert(msg.sender, bytes32)
            )
        ),
        uint256
    )
    
    # Get random fortune index
    fortuneIndex: uint256 = randomSeed % self.fortuneCount
    
    # Get the fortune
    fortune: String[200] = self.fortunes[fortuneIndex]
    
    # Add to user's fortune history if they haven't reached the limit
    userCount: uint256 = self.userFortuneCount[msg.sender]
    if userCount < MAX_USER_FORTUNES:
        self.userFortuneIds[msg.sender][userCount] = fortuneIndex
        self.userFortuneCount[msg.sender] = userCount + 1
    
    # Log the fortune received event
    log FortuneReceived(msg.sender, fortune, fortuneIndex, block.timestamp)
    
    return fortune

# Submit a new fortune (refunds the fortune price)
@payable
@external
def submitFortune(newFortune: String[200]) -> bool:
    # Check if the fortune is valid
    assert len(newFortune) > 0, "Fortune cannot be empty"
    assert len(newFortune) <= MAX_FORTUNE_LENGTH, "Fortune too long"
    
    # Check if payment was made (same as getting a fortune)
    assert msg.value >= self.fortunePrice, "Insufficient payment"
    
    # Add the fortune
    fortuneId: uint256 = self.fortuneCount
    self.fortunes[fortuneId] = newFortune
    self.fortuneCount += 1
    
    # Log the submission
    log FortuneSubmitted(msg.sender, newFortune, fortuneId, block.timestamp)
    
    # Refund the payment
    send(msg.sender, msg.value)
    
    return True

# Vote on a fortune (thumbs up)
@external
def upvoteFortune(fortuneId: uint256):
    assert fortuneId < self.fortuneCount, "Invalid fortune ID"
    
    # Check current vote status
    currentVote: int128 = self.userVotes[msg.sender][fortuneId]
    
    # If already upvoted, do nothing
    if currentVote == VOTE_UP:
        return
    
    # If previously downvoted, remove the downvote first
    if currentVote == VOTE_DOWN:
        self.fortuneDownvotes[fortuneId] -= 1
    
    # Add the upvote
    self.fortuneUpvotes[fortuneId] += 1
    self.userVotes[msg.sender][fortuneId] = VOTE_UP
    
    # Log the vote
    log FortuneVoted(msg.sender, fortuneId, True, block.timestamp)

# Vote on a fortune (thumbs down)
@external
def downvoteFortune(fortuneId: uint256):
    assert fortuneId < self.fortuneCount, "Invalid fortune ID"
    
    # Check current vote status
    currentVote: int128 = self.userVotes[msg.sender][fortuneId]
    
    # If already downvoted, do nothing
    if currentVote == VOTE_DOWN:
        return
    
    # If previously upvoted, remove the upvote first
    if currentVote == VOTE_UP:
        self.fortuneUpvotes[fortuneId] -= 1
    
    # Add the downvote
    self.fortuneDownvotes[fortuneId] += 1
    self.userVotes[msg.sender][fortuneId] = VOTE_DOWN
    
    # Log the vote
    log FortuneVoted(msg.sender, fortuneId, False, block.timestamp)

# Remove vote from a fortune
@external
def removeVote(fortuneId: uint256):
    assert fortuneId < self.fortuneCount, "Invalid fortune ID"
    
    # Check current vote status
    currentVote: int128 = self.userVotes[msg.sender][fortuneId]
    
    # If no vote, do nothing
    if currentVote == VOTE_NONE:
        return
    
    # Remove the vote
    if currentVote == VOTE_UP:
        self.fortuneUpvotes[fortuneId] -= 1
    elif currentVote == VOTE_DOWN:
        self.fortuneDownvotes[fortuneId] -= 1
    
    # Clear the vote
    self.userVotes[msg.sender][fortuneId] = VOTE_NONE
    
    # Log the removal
    log VoteRemoved(msg.sender, fortuneId, block.timestamp)

# Owner can moderate and reject inappropriate fortunes
@external
def rejectFortune(fortuneId: uint256) -> bool:
    assert msg.sender == self.owner, "Only owner can reject fortunes"
    assert fortuneId < self.fortuneCount, "Invalid fortune ID"
    
    # Get the fortune to be rejected
    rejectedFortune: String[200] = self.fortunes[fortuneId]
    
    # Replace with the last fortune to avoid gaps
    if fortuneId != self.fortuneCount - 1:
        self.fortunes[fortuneId] = self.fortunes[self.fortuneCount - 1]
        
        # Also move the votes
        self.fortuneUpvotes[fortuneId] = self.fortuneUpvotes[self.fortuneCount - 1]
        self.fortuneDownvotes[fortuneId] = self.fortuneDownvotes[self.fortuneCount - 1]
        
        # Note: We don't migrate individual user votes as that would be gas-intensive
        # Users who voted on the last fortune will need to re-vote if it's moved
    
    # Decrease count
    self.fortuneCount -= 1
    
    # Log the rejection
    log FortuneRejected(msg.sender, rejectedFortune, block.timestamp)
    
    return True

# Get vote status for a fortune by a user
@view
@external
def getUserVoteOnFortune(user: address, fortuneId: uint256) -> int128:
    assert fortuneId < self.fortuneCount, "Invalid fortune ID"
    return self.userVotes[user][fortuneId]

# Get fortune vote counts
@view
@external
def getFortuneVotes(fortuneId: uint256) -> (uint256, uint256):
    assert fortuneId < self.fortuneCount, "Invalid fortune ID"
    return self.fortuneUpvotes[fortuneId], self.fortuneDownvotes[fortuneId]

# Get top voted fortunes (returns IDs of top 10 fortunes by net votes)
@view
@external
def getTopFortunes() -> uint256[10]:
    topFortunes: uint256[10] = empty(uint256[10])
    topScores: int256[10] = empty(int256[10])
    
    # Iterate through all fortunes
    for i in range(min(self.fortuneCount, 100)):  # Limit to first 100 fortunes for gas efficiency
        netScore: int256 = convert(self.fortuneUpvotes[i], int256) - convert(self.fortuneDownvotes[i], int256)
        
        # Check if this fortune belongs in the top 10
        for j in range(10):
            if netScore > topScores[j]:
                # Shift elements down to make room
                for k in range(9, j, -1):
                    topScores[k] = topScores[k-1]
                    topFortunes[k] = topFortunes[k-1]
                
                # Insert the new fortune
                topScores[j] = netScore
                topFortunes[j] = i
                break
    
    return topFortunes

# Change fortune price (only owner)
@external
def setFortunePrice(newPrice: uint256):
    assert msg.sender == self.owner, "Only owner can change price"
    assert newPrice > 0, "Price must be greater than zero"
    self.fortunePrice = newPrice

# Transfer ownership (only owner)
@external
def transferOwnership(newOwner: address):
    assert msg.sender == self.owner, "Only owner can transfer ownership"
    assert newOwner != empty(address), "Invalid new owner address"
    
    oldOwner: address = self.owner
    self.owner = newOwner
    
    log OwnershipTransferred(oldOwner, newOwner)

# Withdraw funds (only owner)
@external
def withdraw():
    assert msg.sender == self.owner, "Only owner can withdraw"
    send(self.owner, self.balance)

# Get fortune count
@view
@external
def getFortuneCount() -> uint256:
    return self.fortuneCount

# Get fortune by ID
@view
@external
def getFortuneById(fortuneId: uint256) -> String[200]:
    assert fortuneId < self.fortuneCount, "Invalid fortune ID"
    return self.fortunes[fortuneId]

# Get user fortune count
@view
@external
def getUserFortuneCount(user: address) -> uint256:
    return self.userFortuneCount[user]

# Get all fortunes a user has received
@view
@external
def getUserFortunes(user: address) -> (uint256, String[200][100]):
    count: uint256 = self.userFortuneCount[user]
    userFortunes: String[200][100] = empty(String[200][100])
    
    # Populate the array with user's fortunes
    for i in range(min(count, MAX_USER_FORTUNES)):
        fortuneId: uint256 = self.userFortuneIds[user][i]
        userFortunes[i] = self.fortunes[fortuneId]
    
    return count, userFortunes
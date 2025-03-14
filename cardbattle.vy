#pragma version 0.4.1

# Blockchain Card Game: NFT Card Distribution and Battle System

# Interfaces
from vyper.interfaces import ERC721

# Card structure and attributes
struct Card:
    id: uint256
    rarity: uint8  # 1=Common, 2=Uncommon, 3=Rare, 4=Epic, 5=Legendary
    attack: uint256
    health: uint256
    inDeck: bool

# Battle structure
struct Battle:
    level: uint8  # 1-20
    reward: uint256  # ETH reward amount (in wei)
    fee: uint256  # ETH fee to participate (in wei)
    minPower: uint256  # Minimum deck power needed
    enemy1: uint8  # Enemy card ID for position 1
    enemy2: uint8  # Enemy card ID for position 2
    enemy3: uint8  # Enemy card ID for position 3
    enemyAttack: uint256  # Total enemy attack
    enemyHealth: uint256  # Total enemy health

# Game configuration
PACK_PRICE: constant(uint256) = 50000000000000000  # 0.05 ETH
CARDS_PER_PACK: constant(uint8) = 5
MAX_RARITY: constant(uint8) = 5
MAX_CARDS: constant(uint256) = 10000
MAX_CARD_ATTACK: constant(uint256) = 100
MAX_CARD_HEALTH: constant(uint256) = 100
DECK_SIZE: constant(uint8) = 3
MAX_BATTLE_LEVELS: constant(uint8) = 20

# State variables
owner: public(address)
cardCounter: public(uint256)
playerCards: public(HashMap[address, DynArray[uint256, 100]])  # Player -> Array of card IDs
cards: public(HashMap[uint256, Card])  # Card ID -> Card data
battleLevels: public(HashMap[uint8, Battle])  # Level -> Battle data
playerDecks: public(HashMap[address, uint256[3]])  # Player -> Deck (array of 3 card IDs)
randomNonce: uint256

# Events
event CardMinted:
    player: address
    cardId: uint256
    rarity: uint8
    attack: uint256
    health: uint256

event PackOpened:
    player: address
    cardIds: DynArray[uint256, 5]

event DeckUpdated:
    player: address
    cardIds: uint256[3]

event BattleResult:
    player: address
    level: uint8
    won: bool
    reward: uint256

# Initialize contract
@deploy
def __init__():
    self.owner = msg.sender
    self.cardCounter = 0
    self.randomNonce = 0
    
    # Initialize battle levels (1-20)
    for i: uint8 in range(1, MAX_BATTLE_LEVELS + 1):
        level_reward: uint256 = convert(i, uint256) * 10000000000000000  # 0.01 ETH * level
        level_fee: uint256 = convert(i, uint256) * 2000000000000000  # 0.002 ETH * level
        min_power: uint256 = convert(i, uint256) * 30  # Minimum deck power (increases with level)
        
        # Enemy stats scale with level
        enemy_attack: uint256 = convert(i, uint256) * 15
        enemy_health: uint256 = convert(i, uint256) * 20
        
        # Create enemies for this level
        enemy1: uint8 = convert(((convert(i, uint256) - 1) % 3) + 1, uint8)  # Cycles between 1-3
        enemy2: uint8 = convert(((convert(i, uint256) + 1) % 4) + 1, uint8)  # Cycles between 1-4
        enemy3: uint8 = convert(((convert(i, uint256) + 2) % 5) + 1, uint8)  # Cycles between 1-5
        
        self.battleLevels[i] = Battle({
            level: i,
            reward: level_reward,
            fee: level_fee,
            minPower: min_power,
            enemy1: enemy1,
            enemy2: enemy2, 
            enemy3: enemy3,
            enemyAttack: enemy_attack,
            enemyHealth: enemy_health
        })

# Internal function to generate pseudo-random number
@internal
def _random(upper_bound: uint256) -> uint256:
    self.randomNonce += 1
    return convert(keccak256(concat(
        convert(block.timestamp, bytes32),
        convert(block.prevhash, bytes32),
        convert(block.coinbase, bytes32),
        convert(self.randomNonce, bytes32)
    )), uint256) % upper_bound

# Generate card attributes based on rarity
@internal
def _generateCardAttributes(rarity: uint8) -> (uint256, uint256):
    # Higher rarity means better stats
    attack_base: uint256 = 10 * convert(rarity, uint256)
    health_base: uint256 = 15 * convert(rarity, uint256)
    
    # Add some randomness to stats
    attack_random: uint256 = self._random(20)
    health_random: uint256 = self._random(20)
    
    attack: uint256 = min(attack_base + attack_random, MAX_CARD_ATTACK)
    health: uint256 = min(health_base + health_random, MAX_CARD_HEALTH)
    
    return (attack, health)

# Buy and open a card pack
@external
@payable
def buyCardPack():
    assert msg.value >= PACK_PRICE, "Insufficient ETH sent"
    assert self.cardCounter + CARDS_PER_PACK <= MAX_CARDS, "No more cards available"
    
    # Create cards in the pack
    new_card_ids: DynArray[uint256, 5] = []
    
    for i: uint8 in range(CARDS_PER_PACK):
        # Determine card rarity (weighted randomness)
        rarity_roll: uint256 = self._random(100)
        card_rarity: uint8 = 1  # Common by default
        
        # 60% Common, 25% Uncommon, 10% Rare, 4% Epic, 1% Legendary
        if rarity_roll < 60:
            card_rarity = 1  # Common
        elif rarity_roll < 85:
            card_rarity = 2  # Uncommon
        elif rarity_roll < 95:
            card_rarity = 3  # Rare
        elif rarity_roll < 99:
            card_rarity = 4  # Epic
        else:
            card_rarity = 5  # Legendary
        
        # Generate card attributes
        attack, health = self._generateCardAttributes(card_rarity)
        
        # Create new card
        card_id: uint256 = self.cardCounter
        self.cards[card_id] = Card({
            id: card_id,
            rarity: card_rarity,
            attack: attack,
            health: health,
            inDeck: False
        })
        
        # Add card to player's collection
        self.playerCards[msg.sender].append(card_id)
        
        # Emit event
        log CardMinted(msg.sender, card_id, card_rarity, attack, health)
        
        # Add to return array
        new_card_ids.append(card_id)
        
        # Increment card counter
        self.cardCounter += 1
    
    log PackOpened(msg.sender, new_card_ids)

# View player's cards
@view
@external
def getPlayerCards(player: address) -> DynArray[uint256, 100]:
    return self.playerCards[player]

# View card details
@view
@external
def getCardDetails(card_id: uint256) -> (uint8, uint256, uint256, bool):
    card: Card = self.cards[card_id]
    return (card.rarity, card.attack, card.health, card.inDeck)

# Update player's deck
@external
def updateDeck(card_id1: uint256, card_id2: uint256, card_id3: uint256):
    # Verify player owns these cards
    assert self._ownsCard(msg.sender, card_id1), "You don't own card 1"
    assert self._ownsCard(msg.sender, card_id2), "You don't own card 2"
    assert self._ownsCard(msg.sender, card_id3), "You don't own card 3"
    
    # Verify all cards are different
    assert card_id1 != card_id2 and card_id1 != card_id3 and card_id2 != card_id3, "All cards must be different"
    
    # Reset inDeck status for current deck
    current_deck: uint256[3] = self.playerDecks[msg.sender]
    for i: uint256 in range(3):
        if current_deck[i] > 0:
            self.cards[current_deck[i]].inDeck = False
    
    # Update deck
    self.playerDecks[msg.sender] = [card_id1, card_id2, card_id3]
    
    # Mark cards as in deck
    self.cards[card_id1].inDeck = True
    self.cards[card_id2].inDeck = True
    self.cards[card_id3].inDeck = True
    
    log DeckUpdated(msg.sender, [card_id1, card_id2, card_id3])

# Check if player owns a card
@internal
@view
def _ownsCard(player: address, card_id: uint256) -> bool:
    player_cards: DynArray[uint256, 100] = self.playerCards[player]
    for i: uint256 in range(len(player_cards)):
        if player_cards[i] == card_id:
            return True
    return False

# Calculate deck power
@internal
@view
def _calculateDeckPower(deck: uint256[3]) -> (uint256, uint256):
    total_attack: uint256 = 0
    total_health: uint256 = 0
    
    for i: uint256 in range(3):
        card: Card = self.cards[deck[i]]
        total_attack += card.attack
        total_health += card.health
    
    return (total_attack, total_health)

# Enter battle
@external
@payable
def enterBattle(level: uint8):
    # Verify valid battle level
    assert level > 0 and level <= MAX_BATTLE_LEVELS, "Invalid battle level"
    
    battle: Battle = self.battleLevels[level]
    assert msg.value >= battle.fee, "Insufficient battle fee"
    
    # Check if player has a deck
    deck: uint256[3] = self.playerDecks[msg.sender]
    assert deck[0] > 0 and deck[1] > 0 and deck[2] > 0, "Must set up a deck first"
    
    # Calculate player's deck power
    player_attack, player_health = self._calculateDeckPower(deck)
    
    # Check minimum power requirement
    total_power: uint256 = player_attack + player_health
    assert total_power >= battle.minPower, "Deck too weak for this battle level"
    
    # Simulate turns-based battle
    enemy_health: uint256 = battle.enemyHealth
    player_health_remaining: uint256 = player_health
    
    # Simple turn-based simulation with safety limit of 100 rounds
    for i: uint256 in range(100):  # Maximum 100 rounds for safety
        # Player attacks first
        enemy_health = max(0, enemy_health - player_attack)
        
        # Check if enemy defeated
        if enemy_health == 0:
            break
            
        # Enemy attacks
        player_health_remaining = max(0, player_health_remaining - battle.enemyAttack)
        
        # Check if player defeated
        if player_health_remaining == 0:
            break
    
    # Determine winner
    player_win: bool = enemy_health == 0
    
    if player_win:
        # Transfer reward to player
        send(msg.sender, battle.reward)
    
    # Log battle result
    log BattleResult(msg.sender, level, player_win, battle.reward if player_win else 0)

# Get battle level details
@view
@external
def getBattleDetails(level: uint8) -> (uint256, uint256, uint256, uint256, uint256):
    battle: Battle = self.battleLevels[level]
    return (battle.reward, battle.fee, battle.minPower, battle.enemyAttack, battle.enemyHealth)

# View player's current deck
@view
@external
def getPlayerDeck(player: address) -> (uint256[3], uint256, uint256):
    deck: uint256[3] = self.playerDecks[player]
    attack, health = self._calculateDeckPower(deck)
    return (deck, attack, health)

# Withdraw contract funds (owner only)
@external
def withdraw():
    assert msg.sender == self.owner, "Only owner can withdraw"
    send(self.owner, self.balance)

# Transfer ownership
@external
def transferOwnership(new_owner: address):
    assert msg.sender == self.owner, "Only owner can transfer ownership"
    assert new_owner != empty(address), "New owner cannot be zero address"
    self.owner = new_owner
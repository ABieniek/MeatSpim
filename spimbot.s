# syscall constants
PRINT_STRING = 4
PRINT_CHAR   = 11
PRINT_INT    = 1

# debug constants
PRINT_INT_ADDR   = 0xffff0080
PRINT_FLOAT_ADDR = 0xffff0084
PRINT_HEX_ADDR   = 0xffff0088

# spimbot constants
VELOCITY       = 0xffff0010
ANGLE          = 0xffff0014
ANGLE_CONTROL  = 0xffff0018
BOT_X          = 0xffff0020
BOT_Y          = 0xffff0024
OTHER_BOT_X    = 0xffff00a0
OTHER_BOT_Y    = 0xffff00a4
TIMER          = 0xffff001c
SCORES_REQUEST = 0xffff1018

# introduced in lab10
SEARCH_BUNNIES          = 0xffff0054
CATCH_BUNNY             = 0xffff0058
PUT_BUNNIES_IN_PLAYPEN  = 0xffff005c
PLAYPEN_LOCATION        = 0xffff0044

# introduced in labSpimbot
LOCK_PLAYPEN            = 0xffff0048
UNLOCK_PLAYPEN          = 0xffff004c
REQUEST_PUZZLE          = 0xffff00d0
SUBMIT_SOLUTION         = 0xffff00d4
NUM_BUNNIES_CARRIED     = 0xffff0050
NUM_CARROTS             = 0xffff0040
PLAYPEN_OTHER_LOCATION  = 0xffff00dc

# interrupt constants
BONK_MASK               = 0x1000
BONK_ACK                = 0xffff0060
TIMER_MASK              = 0x8000

TIMER_ACK               = 0xffff006c
BUNNY_MOVE_INT_MASK     = 0x400
BUNNY_MOVE_ACK          = 0xffff0020
PLAYPEN_UNLOCK_INT_MASK = 0x2000
PLAYPEN_UNLOCK_ACK      = 0xffff005c
EX_CARRY_LIMIT_INT_MASK = 0x4000
EX_CARRY_LIMIT_ACK      = 0xffff002c
REQUEST_PUZZLE_INT_MASK = 0x800
REQUEST_PUZZLE_ACK      = 0xffff00d8

# Boolean Masks
# use $t9 for Bit Flags
CAN_UNLOCK_ENEMY_PLAYPEN	= 0x00000001	# flag for if the enemy's playpen can be opened
OUR_PLAYPEN_UNLOCKED		= 0x00000002	# flag for if our playpen was opened
PUZZLE_READY			= 0x00000004	# flag for if the puzzle is ready
PUZZLE_REQUESTED		= 0x00000008	# we requested the puzzle, there's no need to request another one
HAS_ENEMY			= 0x00000010	# true if we have an opponent in this simulation
HUNT_BUNNY			= 0x00000020	# true if we should be hunting bunnies right now


.data
# puzzle stuff
turns: .word 1 0 -1 0
# trig stuff
three:	.float	3.0
five:	.float	5.0
PI:	.float	3.141592
F180:	.float  180.0


.align 2
bunnies_data: .space 484
puzzle_data: .space 9804
baskets_data: .space 44
integer_solution: .space 4

##### REGISTER VARIABLE INDEX #####
##### T Registers
# $t0 - temporary (branch condition testing, address holding, ...)
# $t1 - temporary (loop counter)
# $t2 - temporary (address holder)
# $t3 - temporary (weight of heaviest bunny in find_bunny, ....)
# $t4 - temporary (weight of current bunny, ...)
# $t5 - temporary (number of bunnies in bunnies data, ...)
# $t6 - 
# $t7 - address of the bunny we want (set to null if we just caught a bunny)
# $t8 - weight of rabbits we're holding
# $t9 - holds bit flags used for bot's decision making
##### S Registers
# $s0 - x position of our pen
# $s1 - y position of our pen
# $s2 - x position of their pen
# $s3 - y position of their pen
# $s4 - number of carrots we have
# $s5 - number of rabbits we have
# $s6 - 
# $s7 - 

 .text
 main:
	##### Initialization Stuff #####
	# enable interrupts
        li      $t4, TIMER_MASK                 	# timer interrupt enable bit
        or      $t4, $t4, BONK_MASK             	# bonk interrupt bit
        or      $t4, $t4, BUNNY_MOVE_INT_MASK   	# jump interrupt bit
	or	$t4, $t4, REQUEST_PUZZLE_INT_MASK	# puzzle interrupt bit
	or	$t4, $t4, EX_CARRY_LIMIT_INT_MASK	# weight interrupt bit
        or      $t4, $t4, 1				# global interrupt enable
        mtc0    $t4, $12				# set interrupt mask (Status register)

	# set flag for hunting bunnies, there's nothing else we could want to do at the start
	or $t9, $t9, HUNT_BUNNY

	# set flag if we have an enemy
	# reading from any of the enemy bot queries will return -1
	lw $t0, OTHER_BOT_X
	beq $t0, -1, enemy_bot_false	# if the return value is negative 1, skip setting the flag
	or $t9, $t9, HAS_ENEMY
	lw $s3, PLAYPEN_OTHER_LOCATION	# we can also load the x and y position of their pen here
	srl $s2, $s3, 16		# x position of their playpen
	and $s3, $s3, 0x0000ffff	# y position of their playpen
	
enemy_bot_false:
	# give SEARCH_BUNNIES an address to store its information
	# la $t0, bunnies_data
	# sw $t0, SEARCH_BUNNIES
	# might be redundant

	# find location of our pen
	lw $s1, PLAYPEN_LOCATION
	srl $s0, $s1, 16		# x position of our playpen
	and $s1, $s1, 0x0000ffff	# y position of our playpen
	li $s4, 10	# set number of carrots we have (we start with 10)
	# li $s5, 0	# number of rabbits we have, but the register should start with 0

	j start

start:
	# branch to request puzzle
	and $t0, $t9, PUZZLE_REQUESTED
	bgt $t0, $0, no_request
	la $t0, puzzle_data
	sw $t0, REQUEST_PUZZLE
	or $t9, $t9, PUZZLE_REQUESTED
	
no_request:
	# branch to do puzzle
	and $t0, $t9, PUZZLE_READY
	bne $t0, $0, puzzle_init
	j skip_puzzle

puzzle_init:
	bne $s4, 0, skip_puzzle	# if we have carrots, skip the puzzle

	# initialize values for search carrot
	# search_carrot(int max_baskets, int k, Node* root, Baskets* baskets)
	sw $0, VELOCITY	# stop the bot for now

	la $t0, puzzle_data
	li $a0, 10		# max baskets should always be 10
				# @OPT set this value up in the initialization stage and never touch it again
	lw $a1, 9800($t0)	# k is the last word in the puzzle struct
	la $a2, puzzle_data	# root node (?)

	la $a3, baskets_data
	sw $0, baskets_data
	
	## Solving and requesting puzzles
	jal search_carrot
	sw $v0, integer_solution
	la $v0, integer_solution
	sw $v0, SUBMIT_SOLUTION
	add $s4, $s4, 1
	#turn off puzzle ready flag
	la $t0, PUZZLE_READY
	not $t0, $t0
	and $t9, $t9, $t0
	# turn off requested puzzle flag
	la $t0, PUZZLE_REQUESTED
	not $t0, $t0
	and $t9, $t9, $t0
	li $t0, 10
	sw $t0, VELOCITY

skip_puzzle:
	# determine if we're gonna find another bunny
	# @TODO there will probably need to be multiple checks here:
	# check if we have a bunny loaded into the address right now (done)
	# check if we can hold more bunnies
	# check if, in our control flow, we want to be getting another bunny at this moment	
	bne $t7, $0, skip_find_bunny
	jal pick_rabbit			# after this, $t7 should be the address of the rabbit we want

skip_find_bunny:
	jal head_to_destination
	jal check_destination

	j start

##### PICK RABBIT CODE #####

pick_rabbit:
	# @TODO consider cases regarding the enemy player picking up a rabbit:
	# is the bunny still there when we get there?
	# is he heading towards, or close to, the bunny we're looking at right now?
	sub $sp, $sp, 4
	sw $ra, 0($sp)

	la $t2, bunnies_data		# $t1 = address of current bunny
	sw $t2, SEARCH_BUNNIES		# store to SEARCH_BUNNIES to update the bunnies information
	lw $t5, 0($t2)			# number of bunnies in our array
	add $t2, $t2, 4			# 4 offset to skip integer in BunniesInfo struct
	li $t1, 0			# i = 0
	li $t3, -1			# $t3 = weight of heaviest bunny found
	
pick_rabbit_loop:
	# as of right now, I guess I'll just find the heaviest bunny
	# find better algorithm to pick rabbits
	beq $t1, $t5, pick_rabbit_end	# loop through until we surpass the number of bunnies in the array
	lw $t4, 8($t2)			# $t4 = weight of bunny we're looking at
	ble $t4, $t3, pick_rabbit_skip_rabbit
	move $t3, $t4			# max_weight = current_weight
	move $t7, $t2			# target_bunny = this_bunny	

pick_rabbit_skip_rabbit:
	add $t2, $t2, 16		# move pointer to next bunny
	add $t1, $t1, 1			# i++
	j pick_rabbit_loop
	
pick_rabbit_end:
	lw $ra, 0($sp)
	add $sp, $sp, 4
	jr $ra

##### HEAD TO DESTINATION CODE #####

head_to_destination:
	sub $sp, $sp, 4
	sw $ra, 0($sp)
	
	and $t0, $t9, HUNT_BUNNY	# check if we want to be hunting bunnies right now
	bne $t0, HUNT_BUNNY, head_to_destination_end

head_to_destination_bunny:
	# here, I'm gonna assume that $t7 is the address of a bunny, and things will fuck up if it's not
	lw $t0, 0($t7)			# bunny.x
	lw $t1, BOT_X			# bot.x
	sub $a0, $t0, $t1		# bunny.x - bot.x
	lw $t0, 4($t7)  		# bunny.y
	lw $t1, BOT_Y			# bunny.y - bot.y
	sub $a1, $t0, $t1		# bunny.y - bot.y
	# the arguments of arctan are distances from the origin of the circle
	jal sb_arctan			# $v0 is the angle that we want, in degrees
	sw $v0, ANGLE
	li $t0, 1
	sw $t0, ANGLE_CONTROL
	li $t0, 10
	sw $t0, VELOCITY

head_to_destination_end:
	lw $ra, 0($sp)
	add $sp, $sp, 4
	jr $ra

##### CHECK DESTINATION CODE #####

check_destination:
	sub $sp, $sp, 4
	sw $ra, 0($sp)

	and $t0, $t9, HUNT_BUNNY
	bne $t0, HUNT_BUNNY, check_destination_end

check_destination_bunny:
	# same assumption, $t7 better be the address of a bunny
	lw $t0, 0($t7)				# bunny.x
	lw $t1, BOT_X				# bot.x
	sub $a0, $t0, $t1			# bunny.x - bot.x
	lw $t0, 4($t7)  			# bunny.y
	lw $t1, BOT_Y				# bunny.y - bot.y
	sub $a1, $t0, $t1			# bunny.y - bot.y
	# the arguments of the euclidian distance are the distances from the origin of the unit circle
	jal euclidean_dist			# v0 is the distance of our bot to the target bunny
	bgt $v0, 3, check_destination_end	# skip the catch
	#catch the bunny
	lw $t0, 8($t7)
	add $t8, $t8, $t0			# add the weight of the current bunny to the weight held
	sw $t7, CATCH_BUNNY
	sub $s4, $s4, 1				# lose one carrot
	add $s5, $s5, 1
	li $t7, 0				# set target bunny to null
	
check_destination_end:
	lw $ra, 0($sp)
	add $sp, $sp, 4
	jr $ra

##### PROVIDED PUZZLE SOLVER CODE #####	

search_carrot:
	move	$v0, $0			# set return value to 0 early
	beq	$a2, 0, sc_ret		# if (root == NULL), return 0
	beq	$a3, 0, sc_ret		# if (baskets == NULL), return 0

	sub	$sp, $sp, 12
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)

	move	$s0, $a1		# $s0 = int k
	move	$s1, $a3		# $s1 = Baskets *baskets

	sw	$0, 0($a3)		# baskets->num_found = 0

	move	$t0, $0			# $t0 = int i = 0
sc_for:
	bge	$t0, $a0, sc_done	# if (i >= max_baskets), done

	mul	$t1, $t0, 4
	add	$t1, $t1, $a3
	sw	$t0, 4($t1)		# baskets->basket[i] = NULL

	add	$t0, $t0, 1		# i++
	j	sc_for


sc_done:
	move	$a1, $a2
	move	$a2, $a3
	jal	collect_baskets		# collect_baskets(max_baskets, root, baskets)

	move	$a0, $s0
	move	$a1, $s1
	jal	pick_best_k_baskets	# pick_best_k_baskets(k, baskets)

	move	$a0, $s0
	move	$a1, $s1

	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	add	$sp, $sp, 12

	j	get_secret_id		# get_secret_id(k, baskets), tail call

sc_ret:
	jr	$ra

pick_best_k_baskets:
	bne	$a1, 0, pbkb_do
	jr	$ra

pbkb_do:
	sub	$sp, $sp, 32
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)
	sw	$s4, 20($sp)
	sw	$s5, 24($sp)
	sw	$s6, 28($sp)

	move	$s0, $a0			# $s0 = int k
	move	$s1, $a1			# $s1 = Baskets *baskets

	li	$s2, 0				# $s2 = int i = 0
pbkb_for_i:
	bge	$s2, $s0, pbkb_done		# if (i >= k), done

	lw	$s3, 0($s1)
	sub	$s3, $s3, 1			# $s3 = int j = baskets->num_found - 1
pbkb_for_j:
	ble	$s3, $s2, pbkb_for_j_done	# if (j <= i), done

	sub	$s5, $s3, 1
	mul	$s5, $s5, 4
	add	$s5, $s5, $s1
	lw	$a0, 4($s5)			# baskets->basket[j-1]
	jal	get_num_carrots			# get_num_carrots(baskets->basket[j-1])
	move	$s4, $v0

	mul	$s6, $s3, 4
	add	$s6, $s6, $s1
	lw	$a0, 4($s6)			# baskets->basket[j]
	jal	get_num_carrots			# get_num_carrots(baskets->basket[j])

	bge	$s4, $v0, pbkb_for_j_cont	# if (get_num_carrots(baskets->basket[j-1]) >= get_num_carrots(baskets->basket[j])), skip

	## This is very inefficient in MIPS. Can you think of a better way?

	## We're changing the _values_ of the array elements, so we don't need to
	## recompute addresses every time, and can reuse them from earlier.

	lw	$t0, 4($s6)			# baskets->basket[j]
	lw	$t1, 4($s5)			# baskets->basket[j-1]
	xor	$t2, $t0, $t1			# baskets->basket[j] ^ baskets->basket[j-1]
	sw	$t2, 4($s6)			# baskets->basket[j] = baskets->basket[j] ^ baskets->basket[j-1]

	lw	$t0, 4($s6)			# baskets->basket[j]
	lw	$t1, 4($s5)			# baskets->basket[j-1]
	xor	$t2, $t0, $t1			# baskets->basket[j] ^ baskets->basket[j-1]
	sw	$t2, 4($s5)			# baskets->basket[j-1] = baskets->basket[j] ^ baskets->basket[j-1]

	lw	$t0, 4($s6)			# baskets->basket[j]
	lw	$t1, 4($s5)			# baskets->basket[j-1]
	xor	$t2, $t0, $t1			# baskets->basket[j] ^ baskets->basket[j-1]
	sw	$t2, 4($s6)			# baskets->basket[j] = baskets->basket[j] ^ baskets->basket[j-1]

pbkb_for_j_cont:
	sub	$s3, $s3, 1			# j--
	j	pbkb_for_j

pbkb_for_j_done:
	add	$s2, $s2, 1			# i++
	j	pbkb_for_i

pbkb_done:
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	lw	$s4, 20($sp)
	lw	$s5, 24($sp)
	lw	$s6, 28($sp)
	add	$sp, $sp, 32
	jr	$ra

get_secret_id:
	bne	$a1, 0, gsi_do		# if (baskets != NULL), continue
	move	$v0, $0			# return 0
	jr	$ra

gsi_do:
	sub	$sp, $sp, 20
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)

	move	$s0, $a0		# $s0 = int k
	move	$s1, $a1		# $s1 = Baskets *baskets
	move	$s2, $0			# $s2 = int secret_id = 0

	move	$s3, $0			# $s3 = int i = 0
gsi_for:
	bge	$s3, $s0, gsi_return	# if (i >= k), done

	mul	$t0, $s3, 4
	add	$t0, $t0, $s1
	lw	$t0, 4($t0)		# baskets->basket[i]

	lw	$a0, 16($t0)		# baskets->basket[i]->identity
	lw	$a1, 12($t0)		# baskets->basket[i]->id_size
	jal	calculate_identity	# calculate_identity(baskets->basket[i]->identity, baskets->basket[i]->id_size)

	addu	$s2, $s2, $v0		# secret_it += ...

	add	$s3, $s3, 1		# i++
	j	gsi_for

gsi_return:
	move	$v0, $s2		# return secret_id

	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	add	$sp, $sp, 20
	jr	$ra

get_num_carrots:
	bne	$a0, 0, gnc_do		# if (spot != NULL), continue
	move	$v0, $0			# return 0
	jr	$ra

gnc_do:
	lw	$t0, 8($a0)		# spot->dirt
	xor	$t0, $t0, 0x00ff00ff	# $t0 = unsigned int dig = spot->dirt ^ 0x00ff00ff

	and	$t1, $t0, 0xffffff 	# dig & 0xffffff
	sll	$t1, $t1, 8		# (dig & 0xffffff) << 8

	and	$t2, $t0, 0xff000000 	# dig & 0xff00aadi0000
	srl	$t2, $t2, 24		# (dig & 0xff000000) >> 24

	or	$t0, $t1, $t2		# dig = ((dig & 0xffffff) << 8) | ((dig & 0xff000000) >> 24)

	lw	$v0, 4($a0)		# spot->basket
	xor	$v0, $v0, $t0		# return spot->basket ^ dig
	jr	$ra

collect_baskets:
	beq	$a1, 0, cb_ret		# if (spot == NULL), return
	beq	$a2, 0, cb_ret		# if (baskets == NULL), return
	lb	$t0, 0($a1)
	beq	$t0, 1, cb_ret		# if (spot->seen == 1), return

	li	$t0, 1
	sb	$t0, 0($a1)		# spot->seen = 1

	sub	$sp, $sp, 20
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)

	move	$s0, $a0		# $s0 = int max_baskets
	move	$s1, $a1		# $s1 = Node *spot
	move	$s2, $a2		# $s2 = Baskets *baskets

	move	$s3, $0			# $s3 = int i = 0
cb_for:
	lw	$t0, 20($s1)		# spot->num_children
	bge	$s3, $t0, cb_done	# if (i >= spot->num_children), done
	lw	$t0, 0($s2)		# baskets->num_found
	bge	$t0, $s0, cb_done	# if (baskets->num_found >= max_baskets), done

	move	$a0, $s0
	mul	$a1, $s3, 4
	add	$a1, $a1, $s1
	lw	$a1, 24($a1)		# spot->children[i]
	move	$a2, $s2
	jal	collect_baskets		# collect_baskets(max_baskets, spot->children[i], baskets)

	add	$s3, $s3, 1		# i++
	j	cb_for


cb_done:
	lw	$t0, 0($s2)		# baskets->num_found
	bge	$t0, $s0, cb_return	# if (baskets->num_found >= max_baskets), return

	move	$a0, $s1
	jal	get_num_carrots
	ble	$v0, 0, cb_return 	# if (get_num_carrots(spot) <= 0), return

	lw	$t0, 0($s2)		# baskets->num_found
	mul	$t1, $t0, 4
	add	$t1, $t1, $s2
	sw	$s1, 4($t1)		# baskets->basket[baskets->num_found] = spot

	add	$t0, $t0, 1
	sw	$t0, 0($s2)		# baskets->num_found++

cb_return:
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	add	$sp, $sp, 20

cb_ret:
	jr	$ra
	mul	$t0, $s3, 4

calculate_identity:
	sub	$sp, $sp, 36
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)
	sw	$s2, 12($sp)
	sw	$s3, 16($sp)
	sw	$s4, 20($sp)
	sw	$s5, 24($sp)
	sw	$s6, 28($sp)
	sw	$s7, 32($sp)

	move	$s0, $a0		# $s0 = int *v
	move	$s1, $a1		# $s1 = int size

	move	$s2, $s1		# $s2 = int dist = size
	move	$s3, $0			# $s3 = int total = 0
	li	$s4, -1			# $s4 = int idx = -1

	sw	$s1, turns+4		# turns[1] = size
	mul	$t0, $s1, $s4		# -size
	sw	$t0, turns+12		# turns[3] = -size

ci_while:
	ble	$s2, 0, ci_done		# if (dist <= 0), done

	li	$s5, 0			# $s5 = int i = 0
ci_for_i:
	bge	$s5, 4, ci_while 	# if (i >= 4), done

	li	$s6, 0			# $s6 = int j = 0
ci_for_j:
	bge	$s6, $s2, ci_for_j_done # if (j >= dist), dine

	la	$t1, turns
	mul	$t0, $s5, 4
	add	$t0, $t0, $t1		# &turns[i]
	lw	$t0, 0($t0)		# turns[i]
	add	$s4, $s4, $t0		# idx = idx + turns[i]

	move	$a0, $s3		# total

	mul	$s7, $s4, 4
	add	$s7, $s7, $s0		# &v[idx]
	lw	$a1, 0($s7)		# v[idx]

	jal	accumulate		# accumulate(total, v[idx])
	move	$s3, $v0		# total = accumulate(total, v[idx])
	sw	$s3, 0($s7)		# v[idx] = total

	add	$s6, $s6, 1		# j++
	j	ci_for_j

ci_for_j_done:
	rem	$t0, $s5, 2		# i % 2
	bne	$t0, 0, ci_skip		# if (i % 2 != 0), skip
	sub	$s2, $s2, 1		# dist--

ci_skip:
	add	$s5, $s5, 1		# i++
	j	ci_for_i

ci_done:
	move	$a0, $s0		# v
	mul	$a1, $s1, $s1		# size * size
	jal	twisted_sum_array	# twisted_sum_array(v, size * size)

	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	lw	$s2, 12($sp)
	lw	$s3, 16($sp)
	lw	$s4, 20($sp)
	lw	$s5, 24($sp)
	lw	$s6, 28($sp)
	lw	$s7, 32($sp)
	add	$sp, $sp, 36
	jr	$ra

detect_parity:
	li	$t1, 0			# $t1 = int bits_counted = 0
	li	$v0, 1			# $v0 = int return_value = 1

	li	$t0, 0			# $t0 = int i = 0
dp_for:
	bge	$t0, 32, dp_done	# if (i >= INT_SIZE), done

	sra	$t3, $a0, $t0		# number >> i
	and	$t3, $t3, 1		# $t3 = int bit = (number >> i) & 1

	beq	$t3, 0, dp_skip		# if (bit == 0), skip
	add	$t1, $t1, 1		# bits_counted++

dp_skip:
	add	$t0, $t0, 1		# i++
	j	dp_for

dp_done:
	rem	$t3, $t1, 2		# bits_counted % 2
	beq	$t3, 0, dp_ret		# if (bits_counted % 2 == 0), skip
	li	$v0, 0			# return_value = 0

dp_ret:
	jr	$ra			# $v0 is already return_value

accumulate:
	sub	$sp, $sp, 12
	sw	$ra, 0($sp)
	sw	$s0, 4($sp)
	sw	$s1, 8($sp)

	move	$s0, $a0
	move	$s1, $a1

	jal	max_conts_bits_in_common
	blt	$v0, 2, a_dp
	or	$v0, $s0, $s1
	j	a_ret

a_dp:
	move	$a0, $s1
	jal	detect_parity
	bne	$v0, 0, a_mul
	addu	$v0, $s0, $s1
	j	a_ret

a_mul:
	mul	$v0, $s0, $s1

a_ret:
	lw	$ra, 0($sp)
	lw	$s0, 4($sp)
	lw	$s1, 8($sp)
	add	$sp, $sp, 12
	jr	$ra

max_conts_bits_in_common:
	li	$t1, 0			# $t1 = int bits_seen = 0
	li	$v0, 0			# $v0 = int max_seen = 0
	and	$t2, $a0, $a1		# $t2 = int c = a & b

	li	$t0, 0			# $t0 = int i = 0
mcbic_for:
	bge	$t0, 32, mcbic_done	# if (i >= INT_SIZE), done

	sra	$t3, $t2, $t0		# c >> i
	and	$t3, $t3, 1		# $t3 = int bit = (c >> i) & 1

	beq	$t3, 0, mcbic_else 	# if (bit == 0), else
	add	$t1, $t1, 1		# bits_seen++
	j	mcbic_cont

mcbic_else:
	ble	$t1, $v0, mcbic_skip 	# if (bit_seen <= max_seen), skip
	move	$v0, $t1		# max_seen = bits_seen

mcbic_skip:
	li	$t1, 0			# bits_seen = 0

mcbic_cont:
	add	$t0, $t0, 1		# i++
	j	mcbic_for

mcbic_done:
	ble	$t1, $v0, mcbic_ret 	# if (bits_seen <= max_seen), skip
	move	$v0, $t1		# max_seen = bits_seen

mcbic_ret:
	jr	$ra			# $v0 is already max_seen

twisted_sum_array:
	li	$v0, 0			# $v0 = int sum = 0

	li	$t0, 0			# $t0 = int i = 0
tsa_for:
	bge	$t0, $a1, tsa_done	# if (i >= length), done

	sub	$t1, $a1, 1		# length - 1
	sub	$t1, $t1, $t0		# length - 1 - i
	mul	$t1, $t1, 4
	add	$t1, $t1, $a0		# &v[length - 1 - i]
	lw	$t2, 0($t1)		# v[length - 1 - i]
	and	$t2, $t2, 1		# v[length - 1 - i] & 1

	beq	$t2, 0, tsa_skip	# if (v[length - 1 - i] & 1 == 0), skip
	sra	$v0, $v0, 1		# sum >>= 1

tsa_skip:
	mul	$t1, $t0, 4
	add	$t1, $t1, $a0		# &v[i]
	lw	$t2, 0($t1)		# v[i]
	addu	$v0, $v0, $t2		# sum += v[i]

	add	$t0, $t0, 1		# i++
	j	tsa_for

tsa_done:
	jr	$ra			# $v0 is already sum

##### TRIG FUNCTIONS #####


# -----------------------------------------------------------------------
# euclidean_dist - computes sqrt(x^2 + y^2)
# $a0 - x
# $a1 - y
# returns the distance
# -----------------------------------------------------------------------

euclidean_dist:
	mul	$a0, $a0, $a0	# x^2
	mul	$a1, $a1, $a1	# y^2
	add	$v0, $a0, $a1	# x^2 + y^2
	mtc1	$v0, $f0
	cvt.s.w	$f0, $f0	# float(x^2 + y^2)
	sqrt.s	$f0, $f0	# sqrt(x^2 + y^2)
	cvt.w.s	$f0, $f0	# int(sqrt(...))
	mfc1	$v0, $f0
	jr	$ra

# -----------------------------------------------------------------------
# sb_arctan - computes the arctangent of y / x
# $a0 - x
# $a1 - y
# returns the arctangent
# -----------------------------------------------------------------------

# I'm gonna switch some register use here, it uses t registers and it might be fucking up our code
# switching $t0, $t1 to $s0, $s1, and saving them
sb_arctan:
	sub $sp, $sp, 8
	sw $s0, 0($sp)
	sw $s1, 4($sp)

	li	$v0, 0		# angle = 0;

	abs	$s0, $a0	# get absolute values
	abs	$s1, $a1
	ble	$s1, $s0, no_TURN_90	  

	## if (abs(y) > abs(x)) { rotate 90 degrees }
	move	$s0, $a1	# int temp = y;
	neg	$a1, $a0	# y = -x;      
	move	$a0, $s0	# x = temp;    
	li	$v0, 90		# angle = 90;  

no_TURN_90:
	bgez	$a0, pos_x 	# skip if (x >= 0)

	## if (x < 0) 
	add	$v0, $v0, 180	# angle += 180;

pos_x:
	mtc1	$a0, $f0
	mtc1	$a1, $f1
	cvt.s.w $f0, $f0	# convert from ints to floats
	cvt.s.w $f1, $f1
	
	div.s	$f0, $f1, $f0	# float v = (float) y / (float) x;

	mul.s	$f1, $f0, $f0	# v^^2
	mul.s	$f2, $f1, $f0	# v^^3
	l.s	$f3, three	# load 3.0
	div.s 	$f3, $f2, $f3	# v^^3/3
	sub.s	$f6, $f0, $f3	# v - v^^3/3

	mul.s	$f4, $f1, $f2	# v^^5
	l.s	$f5, five	# load 5.0
	div.s 	$f5, $f4, $f5	# v^^5/5
	add.s	$f6, $f6, $f5	# value = v - v^^3/3 + v^^5/5

	l.s	$f8, PI		# load PI
	div.s	$f6, $f6, $f8	# value / PI
	l.s	$f7, F180	# load 180.0
	mul.s	$f6, $f6, $f7	# 180.0 * value / PI

	cvt.w.s $f6, $f6	# convert "delta" back to integer
	mfc1	$s0, $f6
	add	$v0, $v0, $s0	# angle += delta

	lw $s0, 0($sp)
	lw $s1, 4($sp)
	add $sp, $sp, 8
	jr 	$ra

##### INTERRUPT HANDLER #####

.kdata
chunkIH: .space 8
non_intrpt_str: .asciiz "Non-interrupt exception\n"
unhandled_str:  .asciiz "Unhandled interrupt type\n"

.ktext 0x80000180
interrupt_handler:
.set noat
        move $k1, $at                   # set so we can't modify $at
.set at
	# save s registers, restore before returning to main loops
        la $k0, chunkIH
        sw $s0, 0($k0)
        sw $s1, 4($k0)
	sw $s2, 8($k0)
	sw $s3, 12($k0)
	sw $s4, 16($k0)
	sw $s5, 20($k0)
	sw $s6, 24($k0)
	sw $s7, 28($k0)

        mfc0 $k0, $13                   # get cause register
        srl $s0, $k0, 2
        and $s0, $s0, 0xf
        bne $s0, 0, non_intrpt

interrupt_dispatch:
        mfc0 $k0, $13
        beq $k0, $0, done

        and $s0, $k0, 0x1000            # check for bonk interrupt
        bne $s0, 0, bonk_interrupt

        and $s0, $k0, 0x8000            # check for timer interrupt
        bne $s0, 0, timer_interrupt

        and $s0, $k0, 0x400             # check for jump interrupt
        bne $s0, 0, jump_interrupt

	and $s0, $k0, REQUEST_PUZZLE_INT_MASK
	bne $s0, 0, puzzle_interrupt

        # add dispatch for other interrupt types here
        li $v0, 4
        la $s0, unhandled_str
        syscall
        j done

puzzle_interrupt:
	# throws this interrupt when the puzzle has been generated and we can start working on it
	sw $s1, REQUEST_PUZZLE_ACK	# acknowledge
	or $t9, $t9, PUZZLE_READY	# bit flag tells us that the puzzle is ready
	
	j interrupt_dispatch

bonk_interrupt:
        sw $s1, BONK_ACK		# acknowledge
	li $t0, 180
	sw $t0, ANGLE
	sw $0, ANGLE_CONTROL
        #sw $t0, VELOCITY		# stop moving

        j interrupt_dispatch

timer_interrupt:
        sw $s1, TIMER_ACK               # acknowledge
        # @TODO see if I can set up a timer interrupt for when the enemy locks their gate

        j interrupt_dispatch

jump_interrupt:
        sw $s1, BUNNY_MOVE_ACK		# acknowledge
	# @TODO just find the new coordinates of the bunny,
	# it doesn't look like bunnies ever jump that far
	# so I trust that our bot will continue rerouting based on how he loops
	# this might change in the future, though
	
        j interrupt_dispatch

carry_limit_interrupt:
	sw $s1, EX_CARRY_LIMIT_ACK	# acknowledge
	li $t8, 0			# set the weight of our rabbits to 0
	
		

non_intrpt:
        li $v0, 4
        la $s0, non_intrpt_str
        syscall
        j done

done:
	# restore saved registers after handling exceptions
	# try to use as few saved registers as possible, try to
	# minimize loads necessary for s register restoration
        la $k0, chunkIH
        lw $s0, 0($k0)
        lw $s1, 4($k0)
	lw $s2, 8($k0)
	lw $s3, 12($k0)
	lw $s4, 16($k0)	
	lw $s5, 20($k0)
	lw $s6, 24($k0)
	lw $s7, 28($k0)

.set noat
        move $at, $k1
.set at
        eret


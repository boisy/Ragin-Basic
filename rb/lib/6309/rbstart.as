* Ragin' Basic Compiler Start Code
*
* Adapted from C compiler's "cstart.a"
*
* 09-04-85 CK add stack space for one file.
*             branch short on clrbss to ensure clear
* 04-09-86 CK fix memory wrap bug in stkcheck
* 07-27-05 TL Changed to support experimental C compiler ABI.
* 10-31-06 BP Adapted to Basic Compiler
*pushzero       macro     
*               clr       ,-s                 clear a byte on stack
*               endm      

nfiles         equ       3                   stdin,stdout, one extra
Typ            equ       1
Edit           equ       2
Stk            equ       nfiles*256+256+256  files,stack,parms


cr             equ       $0d
sp             equ       $20
comma          equ       ',
dquote         equ       '"
squote         equ       ''

MAXARGS        equ       30                  allow for 30 arguments

*
* rob the first dp byte so nothing gets assigned
* here.  No valid pointer can point to byte zero.
*
               section   dp
__dmy          fcb       0
               endsect   

               section   bss
argv           rmb       2*MAXARGS           pointers to args
argc           rmb       2                   argument counter
_sttop         rmb       2                   stack top
               endsect   

* the following are globally known
               section   bss
memend         rmb       2
_flacc         rmb       8                   floating point & longs accumulator
_mtop          rmb       2                   current non-stack memory top
_stbot         rmb       2                   current stack bottom limit
errno          rmb       2                   global error holder
               endsect   

               section   code
*
* move bytes from source to destination
* 
* Entry:
*  Y = source address
*  U = destination address
*  X = byte count
*
* Exit:
* A, Y, U and X are modified
*
movbytes                 
               lda       ,y+                 get a byte
               sta       ,u+                 put a byte
               leax      -1,x                dec the count
               bne       movbytes            and round again
               rts       


*
* Execution Entry Point
*
_bstart                  
               pshs      y                   save the top of mem
               pshs      u                   save the data beginning address

               clra                          setup to clear
               clrb                          256 bytes
csta05         sta       ,u+                 clear direct page bytes
               decb      
               bne       csta05

csta10         ldx       0,s                 get the beginning of data address (U on stack)
               leau      0,x                 (tfr X,U)
               leax      end,x               get the end of bss address
               pshs      x                   save it
* ASTLE
               leay      etext,pcr           point to DP-data count word

               ldx       ,y++                get count of DP-data to be moved
               beq       csta15              bra if none
               bsr       movbytes            move DP data into position

               ldu       2,s                 get beginning address again
* ASTLE
csta15         leau      dpsiz,u             point to where non-DP should start
               ldx       ,y++                get count of non-DP data to be moved
               beq       csta17
               bsr       movbytes            move non-dp data into position

* clear the bss area - starts where the transferred data finished
csta17         clra      
clrbss         cmpu      0,s                 reached the end?
               beq       reldt               bra if so
               sta       ,u+                 clear it
               bra       clrbss

* now relocate the data-text references
reldt          ldu       2,s                 restore to data bottom
               ldd       ,y++                get data-text ref. count
               beq       reldd
* ASTLE
               leax      btext,pcr           point to text
               lbsr      patch               patch them

* and the data-data refs.
reldd          ldd       ,y++                get the count of data refs.
               beq       restack             bra if none
               leax      0,u                 u was already pointing there
               lbsr      patch

restack        leas      4,s                 reset stack
               puls      x                   restore 'memend'
               stx       memend,u

* process the params
* the stack pointer is back where it started so is
* pointing at the params
*
* the objective is to insert null chars at the end of each argument
* and fill in the argv vector with pointers to them

* first store the program name address
* (an extra name inserted here for just this purpose
* - undocumented as yet)
               sty       argv,u

               ldd       #1                  at least one arg
               std       argc,u
               leay      argv+2,u            point y at second slot
               leax      0,s                 point x at params
               lda       ,x+                 initialize

aloop          ldb       argc+1,u
               cmpb      #MAXARGS-1          about to overflow?
               beq       final
aloop10        cmpa      #cr                 is it EOL?
               beq       final               yes - reached the end of the list

               cmpa      #sp                 is it a space?
               beq       aloop20             yes - try another
               cmpa      #comma              is it a comma?
               bne       aloop30             no - a word has started
aloop20        lda       ,x+                 yes - bump
               bra       aloop10             and round again

aloop30        cmpa      #dquote             quoted string?
               beq       aloop40             yes
               cmpa      #squote             the other one?
               bne       aloop60             no - ordinary

aloop40        stx       ,y++                save address in vector
               inc       argc+1,u            bump the arg count
               pshs      a                   save delimiter

qloop          lda       ,x+                 get another
               cmpa      #cr                 eol?
               beq       aloop50
               cmpa      0,s                 delimiter?
               bne       qloop

aloop50        puls      b                   clean stack
               clr       -1,x
               cmpa      #cr
               beq       final
               lda       ,x+
               bra       aloop

aloop60        leax      -1,x                point at first char
               stx       ,y++                put address in vector
               leax      1,x                 bump it back
               inc       argc+1,u            bump the arg count

* at least one non-space char has been seen
aloop70        cmpa      #cr                 have
               beq       loopend             we
               cmpa      #sp                 reached
               beq       loopend             the end?
               cmpa      #comma              comma?
               beq       loopend
               lda       ,x+                 no - look further
               bra       aloop70

loopend        clr       -1,x                yes - put in the null byte
               bra       aloop               and look for the next word

* now put the pointers on the stack
final          leax      argv,u              get the address of the arg vector
               pshs      x                   goes on the stack first
               ldd       argc,u              get the arg count - leave in D
               pshs      d                   stack it
               bsr       _fixtop             set various variables

               puls      d                   unstack argc
               lbsr      main                call the program
               pshs      d                   put result on stack

*			pushzero						put a zero
*			pushzero						on the stack
               lbsr      exit                and a dummy 'return address'

* no return here
* ASTLE
_fixtop        leax      end,u               get the initial memory end address
               stx       _mtop,u             it's the current memory top
               sts       _sttop,u            this is really two bytes short!
               sts       _stbot,u
               ldd       #-126               give ourselves some breathing space

* on entry here, d holds the negative of a stack reservation request
_stkchec                 
_stkcheck                
               tfr       s,x                 copy sp *02*
               pshs      x                   save it *02*
               leax      d,s                 calculate the requested size
               cmpx      ,s++                check wrap *02*
               bhi       fsterr              *02*
               cmpx      _stbot,u            is it lower than already reserved?
               bhs       stk10               no - return
               cmpx      _mtop,u             yes - is it lower than possible?
               blo       fsterr              yes - can't cope
               stx       _stbot,u            no - reserve it
stk10          rts                           and return

fixserr        fcc       /**** STACK OVERFLOW ****/
               fcb       13

fsterr         leax      <fixserr,pcr        address of error string
               ldb       #E$MemFul           MEMORY FULL error number

erexit         pshs      b                   stack the error number
               lda       #2                  standard error output
               ldy       #100                more than necessary
               os9       I$WritLn            write it
               clr       ,-s                 clear a byte on stack
               lbsr      _exit               and out
* no return here

* stacksize()
* returns the extent of stack requested
* can be used by programmer for guidance
* in sizing memory at compile time
stacksiz                 
               ldd       _sttop,u            top of stack on entry
               subd      _stbot,u            subtract current reserved limit
               rts       

* freemem()
*
* returns the current size of the free memory area in D
freemem                  
               ldd       _stbot,u
               subd      _mtop,u
               rts       

* patch - adjust initialised data which refer to memory locations.
*
* Entry:
*       Y = list of offsets in the data area to be patched
*       U = base of data
*       X = base of either text or data area as appropriate
*       A =  count of offsets in the list
*
* Exit:
*       U - unchanged
*       Y - past the last entry in the list
*       X and D mangled

patch          pshs      x                   save the base
               leax      d,y                 half way up the list
               leax      d,x                 top of list
               pshs      x                   save it as place to stop

* we do not come to this routine with
* a zero count (check!) so a test at the loop top
* is unnecessary
patch10        ldd       ,y++                get the offset
               leax      d,u                 point to location
               ldd       0,x                 get the relative reference
               addd      2,s                 add in the base
               std       0,x                 store the absolute reference
               cmpy      0,s                 reached the top?
               bne       patch10             no - round again

               leas      4,s                 reset the stack
               rts                           and return

               endsect   

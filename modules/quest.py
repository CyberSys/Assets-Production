import Director
def findQuest (playernum,questname,value=1):
    mylen=Director.getSaveDataLength(playernum,questname)
    if (mylen>0):
        myfloat=Director.getSaveData(playernum,questname,0)
        print myfloat
        if (myfloat==value):
            return 1
    return 0
def persistentQuest (playernum,questname):
    print "finding quest"
    print questname
    return findQuest (playernum,questname,-1)
def notLoadedQuest(playernum,questname):
    return not persistentQuest(playernum,questname) and not findQuest (playernum,questname)
def removeQuest (playernum,questname,value=1):
    print "removing quest"
    mylen=Director.getSaveDataLength(playernum,questname)
    if (mylen>0):
        Director.putSaveData(playernum,questname,0,value)
    else:
        Director.pushSaveData(playernum,questname,value)


class quest:
    def setOwner(self,playernum,questname):
        self.name=questname
        self.playernum=playernum
    def removeQuest(self,value=1):
        removeQuest(self.playernum,self.name,value)
    def makeQuestPersistent(self):
        self.removeQuest(-1)
    def Execute(self):
        print "default"
        return 1
class quest_factory:
    def __init__(self,questname,remove_quest_on_run=0):
        self.removequest=remove_quest_on_run
        self.name=questname
    def __eq__(self,oth):
        return self.name==oth.name
    def create (self ):
        return quest()
    def precondition (self,playernum):
        return 1
    def persistent_factory(self,playernum):
        if (persistentQuest(playernum,self.name)):
            print "persistent_factory"
            return self.private_create(playernum)            
        return
    def private_create (self,playernum):
        newquest=self.create()
        newquest.setOwner(playernum,self.name)
        if (self.removequest):
            removeQuest(playernum,self.name)
        return newquest        
    def factory (self,playernum):
        if (self.precondition(playernum)):
            if (notLoadedQuest (playernum,self.name)):
                print "nonpfact"            
                return self.private_create(playernum)
        return
            
class test_quest (quest):
    def __init__ (self):
        self.i=0
    def Execute (self):
        print self.i
        self.i+=1
        if (self.i>100):
            self.removeQuest()
            return 0
        return 1

class test_quest_factory (quest_factory):
    def __init__ (self):
        quest_factory.__init__ (self,"drone_quest")
    def create (self):
        return test_quest()




module ai_orderlist {

  import vec3;
  import random;

  // ================== module variables ==================

  // variables for the module (not classes)

  float resolution; // how often should I check
  float resolution_delta; // delta for resolution
  object null_target; // gets set to null

  // ================== module routines ==================

  // routines for the module (not classes)

  void orderFlyTo(object order_list,object wp_name,object waypoint_pos,float speed,bool afterburner,float abort_range){
    object new_submap=_omap.new();

    _omap.set(new_submap,"order","flyto");
    _omap.set(new_submap,"wp_name",wp_name);
    _omap.set(new_submap,"wp_pos",waypoint_pos);
    _omap.set(new_submap,"speed",speed);
    _omap.set(new_submap,"afterburner",afterburner);
    _omap.set(new_submap,"abort_range",abort_range);

    _olist.push_back(order_list,new_submap);
  };

  // -----------------------------------------------------------

  void orderDefend(object order_list,float defend_range){
    object new_submap=_omap.new();

    _omap.set(new_submap,"order","defend");
    _omap.set(new_submap,"defend_range",defend_range);

    _olist.push_back(order_list,new_submap);
  };

  // -----------------------------------------------------------

  void orderAttack(object order_list,float attack_range){
    object new_submap=_omap.new();

    _omap.set(new_submap,"order","attack");
    _omap.set(new_submap,"attack_range",attack_range);

    _olist.push_back(order_list,new_submap);
  };

  // -----------------------------------------------------------

  void orderPatrol(object order_list,object wp_name,object waypoint,int patrol_mode,float speed,float patrol_range){
    object new_submap=_omap.new();

    _omap.set(new_submap,"order","patrol");
    _omap.set(new_submap,"wp_name",wp_name);
    _omap.set(new_submap,"waypoint",waypoint);
    _omap.set(new_submap,"patrol_mode",patrol_mode);
    _omap.set(new_submap,"speed",speed);
    _omap.set(new_submap,"patrol_range",patrol_range);

    _olist.push_back(order_list,new_submap);
  };

  // -----------------------------------------------------------

  object newOrderList(){
    object olist=_olist.new();
    
    return olist;
  };

  // -----------------------------------------------------------

  void init(){
    resolution=3.0;
    resolution_delta=1.0;

    _std.setNull(null_target);
  };

  // -----------------------------------------------------------


  // ================= ai class variables ====================

  // these are arguments for the classes
  class object my_order_list;

  class bool _done;

  //class variables used for the ais
  class object my_done_list; // keeps track which orders are already done
  class object my_outstr;
  class object my_unit; // my ship
  class object my_order; // this order the ai script is
  class object my_fgid; // my flightgroup id
  class float my_resolution; 
  class object my_last_order; // the currently executed order
  class object my_last_order_id; // the index of the order
  class float my_last_time; // for checking time with my_resolution
  class int my_mode; // current order mode
  class object my_flyto_unit; //if flyto: the unit where I flyto
  class object my_flyto_pos; //if flyto: the position I am flying to
  class int my_fgnum; // my subnumber in the flightgroup
  class object my_fgname; // flightgroup name

  class float my_nearest_enemy_dist; // the distance to nearest enemy
  class float my_nearest_friend_dist;
  class float my_nearest_ship_dist;

  class object my_threat;
  class object my_nearest_friend;
  class object my_nearest_enemy;
  class object my_nearest_ship;

  class object my_leader;

  class object my_flyto_map; //if flyto: the flyto-command-map I use

  // should I do this or that?
  class bool my_do_defend;
  class bool my_do_attack;
  class bool my_do_flyto;
  class bool my_do_patrol;

  // ================= ai class methods  ====================

  void checkFlyto(object submap){
    my_do_flyto=true;
    my_flyto_map=submap;
  };

  // -----------------------------------------------------------

  void checkDefend(object submap){
    float defend_range=_omap.get(submap,"defend_range");

    if(my_nearest_enemy_dist<defend_range){
      my_do_defend=true;
    }
    else{
      my_do_defend=false;
    }
  };

  // -----------------------------------------------------------

  void checkAttack(object submap){
    float attack_range=_omap.get(submap,"attack_range");

    if(my_nearest_enemy_dist<attack_range){
      my_do_attack=true;
    }
    else{
      my_do_attack=false;
    }
  };

  // -----------------------------------------------------------

  void checkPatrol(object submap){
    
  };

  // -----------------------------------------------------------

  void executeOrder(){
    //    _io.printf("%s: executing order\n",my_fgid);
    //my_do_attack=false;
    //    _io.printf("%s: attack=%b defend=%b flyto=%b\n",my_fgid,my_do_attack,my_do_defend,my_do_flyto);
    if(my_do_attack){
      // I should attack
      _io.printf("%s: executing order attack0\n",my_fgid);
      if(my_mode!=0){
	// we switch from other to attack mode
	_io.printf("%s: executing order attack1\n",my_fgid);
	my_mode=0;

	_order.eraseOrder(my_order,my_last_order);

	my_last_order=_order.newAggressiveAI("default.agg.xml","default.int.xml");
	_order.enqueueOrder(my_order,my_last_order);
      }
    }
    else if(my_do_defend){
      // I should defend myself
      if(my_mode!=1){
	// we switch do defend mode
	_io.printf("%s: executing order defend\n",my_fgid);
	my_mode=1;

	my_last_order=_order.newAggressiveAI("default.agg.xml","default.int.xml");
	_order.enqueueOrder(my_order,my_last_order);
      }
    }
    else if(my_do_flyto){
      // I should fly to somewhere
      if(my_mode!=2){
	// switch to flyto mode
	initFlyto();
      }
    }
    else if(my_do_patrol){
      // I should patrol
    _io.printf("%s: executing order patrol\n",my_fgid);

      if(my_mode!=3){
	//switch to patrol mode
	initPatrol();
      }
    }
    else{
      // standard action
      if(my_mode!=(0-1)){
	initStdAction();
      }
    }

  };

  // -----------------------------------------------------------

  void initFlyto(){
    _io.printf("%s: init flyto\n",my_fgid);
    my_mode=2;

    object wp_name=_omap.get(my_flyto_map,"wp_name");
    object wp_pos=_omap.get(my_flyto_map,"wp_pos");
    float speed=_omap.get(my_flyto_map,"speed");
    bool afterburner=_omap.get(my_flyto_map,"afterburner");
    float abort_range=_omap.get(my_flyto_map,"abort_range");

    _io.printf("%s: init flyto2\n",my_fgid);
    _order.eraseOrder(my_order,my_last_order);
    _io.printf("%s: init flyto3\n",my_fgid);

    if(!_string.equal(wp_name,"-none-")){
      // we don't fly to a position, but to a unit
      _io.printf("%s: init flyto unit\n",my_fgid);
      my_flyto_unit=unit.getUnitByFgID(wp_name);

      if(_std.isNull(my_flyto_unit)){
	_io.printf("waypoint not found\n");
      }
      else if(_unit.isJumppoint(my_flyto_unit)){
	// we have to fly to a jumppoint
	my_last_order=_order.newFlyToJumppoint(my_flyto_unit,speed,afterburner);
      }
      else{
	// normal unit
	_io.printf("%s: init flyto10\n",my_fgid);
	_olist.delete(my_flyto_pos);

	my_flyto_pos=_unit.getPosition(my_flyto_unit);

	my_last_order=_order.newFlyToWaypoint(my_flyto_pos,speed,afterburner,abort_range);
      }
    }
    else{
      // we already gave a position
      _olist.delete(my_flyto_pos);
      my_flyto_pos=wp_pos;

      my_last_order=_order.newFlyToWaypoint(my_flyto_pos,speed,afterburner,abort_range);
    }

    _order.enqueueOrder(my_order,my_last_order);

    _unit.setTarget(my_unit,null_target);
  };

  // -----------------------------------------------------------

  void initPatrol(){
  };

  void initStdAction(){
    _io.printf("init stdaction\n");
    object pos=_unit.getPosition(my_unit);
    my_last_order=_order.newPatrol(0,pos,500.0,null_target,0.6);

    _order.enqueueOrder(my_order,my_last_order);
    //_olist.delete(pos);
  };

  // -----------------------------------------------------------

  void scanSystem(){
    my_threat=_unit.getThreat(my_unit);

    int ship_nr=0;
    float min_enemy_dist=9999999.0;
    float min_friend_dist=9999999.0;
    float min_ship_dist=9999999.0;
    object min_enemy;
    object min_friend;
    object min_ship;

    _std.setNull(min_enemy);
    _std.setNull(min_friend);
    _std.setNull(min_ship);

    int leader_num=my_fgnum;
    my_leader=my_unit;

    object unit=_unit.getUnit(ship_nr);
    
    while((!_std.isNull(unit))){
      if(!_std.equal(my_unit,unit)){
	//	_io.printf("%s: checking ship %d\n",my_fgid,ship_nr);
	object unit_pos=_unit.getPosition(unit);
	float dist=_unit.getMinDis(my_unit,unit_pos);
	float relation=_unit.getRelation(my_unit,unit);

	if(relation<0.0){
	  //we are enmies
	  if(dist<min_enemy_dist){
	    min_enemy_dist=dist;
	    min_enemy=unit;
	  }
	}
	if(relation>0.0){
	  //we are friends
	  if(dist<min_friend_dist){
	    min_friend_dist=dist;
	    min_friend=unit;
	  }
	  // check for flightgroup leader
	  object fgname=_unit.getFgName(unit);
	  if(_string.equal(my_fgname,fgname)){
	    // it's a ship from our flightgroup
	    int fgnum=_unit.getFgSubnumber(unit);
	    if(fgnum<leader_num){
	      //set this to be our leader
	      my_leader=unit;
	      leader_num=fgnum;
	    }
	  }
	}
	// for all ships
	if(dist<min_ship_dist){
	  min_ship_dist=dist;
	  min_ship=unit;
	}
	
	_olist.delete(unit_pos);
      }
      ship_nr=ship_nr+1;
      unit=_unit.getUnit(ship_nr);
    }

    my_nearest_enemy_dist=min_enemy_dist;
    my_nearest_enemy=min_enemy;

    my_nearest_friend_dist=min_friend_dist;
    my_nearest_friend=min_friend;

    my_nearest_ship_dist=min_ship_dist;
    my_nearest_ship=min_ship;

    //        _io.printf("%s: system scanned\n",my_fgid);
  };

  // -----------------------------------------------------------

  void checkModes(){
    my_do_attack=false;
    my_do_defend=false;
    my_do_flyto=false;
    my_do_patrol=false;

    //    _io.printf("%s: checking modes\n",my_fgid);
    int size=_olist.size(my_order_list);

    int i=0;
    while(i<size){
      bool done_order=_olist.at(my_done_list,i);
      if(!done_order){
	object submap=_olist.at(my_order_list,i);
      
	object order=_omap.get(submap,"order");
	//      _io.printf("%s: order[%d]=%s\n",my_fgid,i,order);

	if(_string.equal(order,"flyto")){
	  checkFlyto(submap);
	}
	else if(_string.equal(order,"defend")){
	  checkDefend(submap);
	}
	else if(_string.equal(order,"attack")){
	  checkAttack(submap);
	}
	else if(_string.equal(order,"patrol")){
	  checkPatrol(submap);
	}
      }
      i=i+1;
    }
    
    executeOrder();
  };

  // -----------------------------------------------------------

  void checkLastModeAbort(){
    object found_order=_order.findOrder(my_order,my_last_order);

    if(_std.isNull(found_order)){
      // the last issued order has quit
      _io.printf("%s: order has quit\n",my_fgid);
      
      //      _olist.set(my_done_list,my_last_order_id,true);
    }
  };

  // -----------------------------------------------------------

  void initDoneList(){
    my_done_list=_olist.new();
    int size=_olist.size(my_order_list);
    bool bval=false;

    int i=0;
    while(i<size){
      object submap=_olist.at(my_order_list,i);
      _olist.push_back(my_done_list,bval);
      i=i+1;
    }
  };

  // -----------------------------------------------------------

  void initai(){
    my_outstr=_string.new();
    my_flyto_pos=_olist.new();

    my_unit=_std.getCurrentAIUnit();
    my_order=_std.getCurrentAIOrder();

    my_fgid=_unit.getFgID(my_unit);
    my_fgnum=_unit.getFgSubnumber(my_unit);
    my_fgname=_unit.getFgName(my_unit);

    my_resolution=resolution+random.random(0.0-resolution_delta,resolution_delta);
    _io.printf("%s: my_resulution=%f\n",my_fgid,my_resolution);

    //last_order=_order.newFlyToWaypoint(waypoint,vel,afterburner,abort_range);
    //_order.enqueueOrder(my_order,last_order);

    initDoneList();

    scanSystem();

    initStdAction();

    checkModes();

    _done=false;

    my_last_time=_std.getGameTime();
  };

  // -----------------------------------------------------------

  void executeai(){
    float new_time=_std.getGameTime();

    if((my_last_time+my_resolution)<new_time){
      _io.printf("%s: checking\n",my_fgid);
      checkLastModeAbort();
      scanSystem();
      checkModes();
      my_last_time=new_time;
    }
  };

  // -----------------------------------------------------------

  void quitai(){
    _io.printf("ai_orderlist quitting\n");
    _string.delete(my_outstr);
  };

}

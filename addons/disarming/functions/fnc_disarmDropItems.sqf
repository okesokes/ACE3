/*
 * Author: PabstMirror
 * Makes a unit drop items
 *
 * Arguments:
 * 0: caller (player) <OBJECT>
 * 1: target <OBJECT>
 * 2: classnamess <ARRAY>
 * 3: Do Not Drop Ammo <BOOL><OPTIONAL>
 *
 * Return Value:
 * Nothing
 *
 * Example:
 * [player, cursorTarget, ["ace_bandage"]] call ace_disarming_fnc_disarmDropItems
 *
 * Public: No
 */
#include "script_component.hpp"

#define TIME_MAX_WAIT 5

PARAMS_3(_caller,_target,_listOfItemsToRemove);
DEFAULT_PARAM(3,_doNotDropAmmo,false); //By default units drop all weapon mags when dropping a weapon

_fncSumArray = {
    _return = 0;
    {_return = _return + _x;} forEach (_this select 0);
    _return
};

//Sanity Checks
if (!([_target] call FUNC(canBeDisarmed))) exitWith {
    [_caller, _target, "Debug: Cannot disarm target"] call FUNC(eventTargetFinish);
};
if (_doNotDropAmmo && {({_x in _listOfItemsToRemove} count (magazines _target)) > 0}) exitWith {
    [_caller, _target, "Debug: Trying to drop magazine with _doNotDropAmmo flag"] call FUNC(eventTargetFinish);
};

_holder = objNull;

//If not dropping ammo, don't use an existing container
if (!_doNotDropAmmo) then {
    {
        if ((_x getVariable [QGVAR(disarmUnit), objNull]) == _target) exitWith {
            _holder = _x;
        };
    } forEach ((getpos _target) nearObjects [DISARM_CONTAINER, 3]);
};

if (isNull _holder) then {
    _dropPos = _target modelToWorld [0, 0.75, 0];
    _dropPos set [2, ((getPosASL _target) select 2)];
    // _holder = createVehicle ["WeaponHolderSimulated", _dropPos, [], 0, "CAN_COLLIDE"];
    _holder = createVehicle [DISARM_CONTAINER, _dropPos, [], 0, "CAN_COLLIDE"];
    _holder setPosASL _dropPos;
    _holder setVariable [QGVAR(holderInUse), false];
    _holder setVariable [QGVAR(disarmUnit), _target, true];
};

//Verify holder created
if (isNull _holder) exitWith {
    [_caller, _target, "Debug: Null Holder"] call FUNC(eventTargetFinish);
};
//Make sure only one drop operation at a time (using PFEH system as a queue)
if (_holder getVariable [QGVAR(holderInUse), false]) exitWith {
    systemChat format ["Debug: %1 - Ground Container In Use, waiting until free", time];
    [{
        _this call FUNC(disarmDropItems);
    }, _this, 0, 0] call EFUNC(common,waitAndExecute);
};
_holder setVariable [QGVAR(holderInUse), true];


//Remove Magazines
_targetMagazinesStart = magazinesAmmo _target;
_holderMagazinesStart = magazinesAmmoCargo _holder;

{
    EXPLODE_2_PVT(_x,_xClassname,_xAmmo);
    if ((_xClassname in _listOfItemsToRemove) && {!(_xClassname in UNIQUE_MAGAZINES)}) then {
        _holder addMagazineAmmoCargo [_xClassname, 1, _xAmmo];
        _target removeMagazine _xClassname;
    };
} forEach _targetMagazinesStart;

_targetMagazinesEnd = magazinesAmmo _target;
_holderMagazinesEnd = magazinesAmmoCargo _holder;

//Verify Mags dropped from unit:
if ( ({(_x select 0) in _listOfItemsToRemove} count _targetMagazinesEnd) != 0) exitWith {
    _holder setVariable [QGVAR(holderInUse), false];
    [_caller, _target, "Debug: Didn't Remove Magazines"] call FUNC(eventTargetFinish);
};
//Verify holder has mags unit had 
if (!([_targetMagazinesStart, _targetMagazinesEnd, _holderMagazinesStart, _holderMagazinesEnd] call FUNC(verifyMagazinesMoved))) then {
    ERR = [_targetMagazinesStart, _targetMagazinesEnd, _holderMagazinesStart, _holderMagazinesEnd];
    _holder setVariable [QGVAR(holderInUse), false];
    [_caller, _target, "Debug: Crate Magazines not in holder"] call FUNC(eventTargetFinish);
};

//Remove Items, Assigned Items and NVG
_holderItemsStart = getitemCargo _holder;
_targetItemsStart = (assignedItems _target) + (items _target);
if ((headgear _target) != "") then {_targetItemsStart pushBack (headgear _target);};
if ((goggles _target) != "") then {_targetItemsStart pushBack (goggles _target);};


_addToCrateClassnames = [];
_addToCrateCount = [];
{
    if (_x in _listOfItemsToRemove) then {
        if (_x in (items _target)) then {
            _target removeItem _x;
        } else {
            _target unlinkItem _x;
        };
        _index = _addToCrateClassnames find _x;
        if (_index != -1) then {
            _addToCrateCount set [_index, ((_addToCrateCount select _index) + 1)];
        } else {
            _addToCrateClassnames pushBack _x;
            _addToCrateCount pushBack 1;
        };
    };
} forEach _targetItemsStart;

//Add the items to the holder (combined to reduce addItemCargoGlobal calls)
{
    _holder addItemCargoGlobal [(_addToCrateClassnames select _forEachIndex), (_addToCrateCount select _forEachIndex)];
} forEach _addToCrateClassnames;

_holderItemsEnd = getitemCargo _holder;
_targetItemsEnd = (assignedItems _target) + (items _target);
if ((headgear _target) != "") then {_targetItemsEnd pushBack (headgear _target);};
if ((goggles _target) != "") then {_targetItemsEnd pushBack (goggles _target);};

//Verify Items Added
if (((count _targetItemsStart) - (count _targetItemsEnd)) != ([_addToCrateCount] call _fncSumArray)) exitWith {
    _holder setVariable [QGVAR(holderInUse), false];
    [_caller, _target, "Debug: Items Not Removed From Player"] call FUNC(eventTargetFinish);
};
if ((([_holderItemsEnd select 1] call _fncSumArray) - ([_holderItemsStart select 1] call _fncSumArray)) != ([_addToCrateCount] call _fncSumArray)) exitWith {

    _holder setVariable [QGVAR(holderInUse), false];
    [_caller, _target, "Debug: Items Not Added to Holder"] call FUNC(eventTargetFinish);
};


//If holder is still empty, it will be 'garbage collected' while we wait for the drop 'action' to take place
//So add a dummy item and just remove at the end
_holderIsEmpty = ([_holder] call FUNC(getAllGearContainer)) isEqualTo [[],[]];
if (_holderIsEmpty) then {
    systemChat "Debug: making dummy";
    _holder addItemCargoGlobal [DUMMY_ITEM, 1];
};

systemChat format ["PFEh start %1", time];
//Start the PFEH to do the actions (which could take >1 frame)
[{
    PARAMS_2(_args,_pfID);
    EXPLODE_8_PVT(_args,_caller,_target,_listOfItemsToRemove,_holder,_holderIsEmpty,_maxWaitTime,_doNotDropAmmo,_startingMagazines);

    _needToRemoveWeapon = ({_x in _listOfItemsToRemove} count (weapons _target)) > 0;
    _needToRemoveMagazines = ({_x in _listOfItemsToRemove} count (magazines _target)) > 0;
    _needToRemoveBackpack = ((backPack _target) != "") && {(backPack _target) in _listOfItemsToRemove};
    _needToRemoveVest = ((vest _target) != "") && {(vest _target) in _listOfItemsToRemove};
    _needToRemoveUniform = ((uniform _target) != "") && {(uniform _target) in _listOfItemsToRemove};

    if ((time < _maxWaitTime) && {[_target] call FUNC(canBeDisarmed)} && {_needToRemoveWeapon || _needToRemoveMagazines || _needToRemoveBackpack}) then {
        //action drop weapons (keeps loaded magazine and attachements)
        {
            if (_x in _listOfItemsToRemove) then {
                _target action ["DropWeapon", _holder, _x];
            };
        } forEach (weapons _target);

        //Drop magazine (keeps unique ID)
        {
            if (_x in _listOfItemsToRemove) then {
                _target action ["DropMagazine", _holder, _x];
            };
        } forEach (magazines _target);

        //Drop backpack (Keeps variables for ACRE/TFR)
        if (_needToRemoveBackpack) then {_target action ["DropBag", _holder, (backPack _target)];};
    } else {
        systemChat format ["PFEh done %1", time];
        //Exit PFEH
        [_pfID] call CBA_fnc_removePerFrameHandler;


        if (_doNotDropAmmo) then {
            _error = false;

            _magsToPickup = +_startingMagazines;
            {
                _index = _magsToPickup find _x;
                if (_index == -1) exitWith {_error = true; ERROR("More mags than when we started?")};
                _magsToPickup deleteAt _index;
            } forEach (magazinesAmmo _target);

            _magazinesInHolder = magazinesAmmoCargo _holder;
            {
                _index = _magazinesInHolder find _x;
                if (_index == -1) exitWith {_error = true; ERROR("Missing mag not in holder")};
                _magazinesInHolder deleteAt _index;
            } forEach _magsToPickup;

            //No Error (all the ammo in the container is ammo we should have);
            if ((!_error) && {_magazinesInHolder isEqualTo []}) then {
                {
                    _target addMagazine _x;
                } forEach (magazinesAmmoCargo _holder);
                clearMagazineCargoGlobal _holder;
            };
        };

        //If we added a dummy item, remove it now
        if (_holderIsEmpty && {!((getItemCargo _holder) isEqualTo [[DUMMY_ITEM],[1]])}) exitWith {
            _holder setVariable [QGVAR(holderInUse), false];
            [_caller, _target, "Debug: Holder should only have dummy item"] call FUNC(eventTargetFinish);
        };
        if (_holderIsEmpty) then {
            systemChat "Debug: Deleting Dummy";
            clearItemCargoGlobal _holder;
        };
        //Verify we didn't timeout waiting on drop action
        if (time >= _maxWaitTime)  exitWith {
            _holder setVariable [QGVAR(holderInUse), false];
            [_caller, _target, "Debug: Drop Actions Timeout"] call FUNC(eventTargetFinish);
        };
        //If target lost disarm status:
        if (!([_target] call FUNC(canBeDisarmed))) exitWith {
            _holder setVariable [QGVAR(holderInUse), false];
            [_caller, _target, "Debug: Target cannot be disarmed"] call FUNC(eventTargetFinish);
        };
        if (_needToRemoveVest && {!((vestItems _target) isEqualTo [])}) exitWith {
            _holder setVariable [QGVAR(holderInUse), false];
            [_caller, _target, "Debug: Vest Not Empty"] call FUNC(eventTargetFinish);
        };
        if (_needToRemoveVest) then {
            removeVest _target;
            _holder addItemCargoGlobal [(vest _target), 1];
        };
        if (_needToRemoveUniform && {!((uniformItems _target) isEqualTo [])}) exitWith {
            _holder setVariable [QGVAR(holderInUse), false];
            [_caller, _target, "Debug: Uniform Not Empty"] call FUNC(eventTargetFinish);
        };
        if (_needToRemoveUniform) then {
            removeUniform _target;
            _holder addItemCargoGlobal [(uniform _target), 1];
        };

        _holder setVariable [QGVAR(holderInUse), false];
        [_caller, _target, ""] call FUNC(eventTargetFinish);
    };

}, 0.0, [_caller,_target, _listOfItemsToRemove, _holder, _holderIsEmpty, (time + TIME_MAX_WAIT), _doNotDropAmmo, _targetMagazinesEnd]] call CBA_fnc_addPerFrameHandler;
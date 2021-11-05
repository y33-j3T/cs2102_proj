-- create a booking in the future (2 time slots)
-- add 4 employees to that meeting 
-- approve that meeting
-- update capacity of the meeting room to be 3
-- Expected result: that meeting should be removed

CALL book_room (2, 3, '2021-11-13', 10, 12, 26);
CALL join_meeting (2, 3, '2021-11-13', 10, 12, 1);
CALL join_meeting (2, 3, '2021-11-13', 10, 12, 2);
CALL join_meeting (2, 3, '2021-11-13', 10, 12, 3);
CALL join_meeting (2, 3, '2021-11-13', 10, 12, 4);
CALL join_meeting (2, 3, '2021-11-13', 10, 12, 12);
CALL approve_meeting (2, 3, '2021-11-13', 10, 12, 2);
-- -- meeting booked with eid 26, 1, 2 on day D 

SELECT * FROM Sessions WHERE date = '2021-11-13';
SELECT * FROM Joins WHERE date = '2021-11-13';

-- change capacity at floor 2, room 3 to 5, by eid = 2
CALL change_capacity (2, 3, 5, 2);

SELECT * FROM Sessions WHERE date = '2021-11-13';
SELECT * FROM Joins WHERE date = '2021-11-13';

CALL change_capacity (2, 3, 10, 2);

CALL unbook_room (2, 3, '2021-11-13', 10, 12, 26); 

-- In running this script a second time, employee 12 cannot join, 
-- because # of people exceeds the capacity
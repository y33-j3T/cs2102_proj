-- hours larger than 1 hour and must be available
-- ascending order of capacity
CREATE OR REPLACE FUNCTION search_room(search_capacity INT, search_date DATE, start_time INT, end_time INT)
    RETURNS TABLE
            (
                floor    INT,
                room     INT,
                did      INT,
                capacity INT
            )
AS
$$
BEGIN
    SELECT M.floor, M.room, M.did, U.new_cap
    FROM Updates U
             JOIN MeetingRooms M
                  ON U.room = M.room AND U.floor = M.floor
         -- capacity check for the most recent update before that date
    WHERE search_capacity <= (SELECT U2.new_cap
                              FROM Updates U2
                              WHERE U2.date <= search_date
                                AND U2.floor = M.floor
                                AND U2.room = M.room
                              ORDER BY U2.date DESC
                              LIMIT 1)
      AND U.date = (SELECT U3.date
                    FROM Updates U3
                    WHERE U3.date <= search_date
                      AND U3.floor = M.floor
                      AND U3.room = M.room
                    ORDER BY U3.date DESC
                    LIMIT 1)
      -- Not any slot in the period is taken
      AND NOT EXISTS(SELECT 1
                     FROM sessions S
                     where S.floor = M.floor
                       and S.room = M.room
                       and S.date = search_date
                       and S.time >= start_time
                       and S.time < end_time)
    ORDER BY U.new_cap, M.floor, M.room;
END;
$$ LANGUAGE plpgsql;


-- eid of the employee booking the room
-- assume that can book multiple 1 hour slot
-- to consider : allow booking at odd time like 10:30
CREATE OR REPLACE PROCEDURE book_room(book_floor INT, book_room INT, book_date DATE, start_time INT, end_time INT,
                                      eid_booker INT)
AS
$$

declare
    sessions_not_available int;
    is_booker              boolean;
    curr_time              int;
BEGIN
    sessions_not_available := (SELECT count(*)
                               FROM sessions S
                               WHERE S.date = book_date
                                 AND S.room = book_room
                                 AND S.floor = book_floor
                                 AND (S.time >= start_time AND S.time < end_time));

    curr_time = start_time;
    is_booker := EXISTS(SELECT 1 FROM Booker B WHERE eid_booker = B.eid);
    IF is_booker AND sessions_not_available = 0 AND end_time < 24 THEN
        while curr_time < end_time
            loop
                INSERT INTO sessions(date, time, room, floor, eid_booker)
                VALUES (book_date, curr_time, book_room, book_floor, eid_booker);
                INSERT INTO joins(eid, date, time, room, floor)
                VALUES (eid_booker, book_date, curr_time, book_room, book_floor);
                curr_time := curr_time + 1;
            end loop;
    END IF;
END;
$$
    language plpgsql;


-- un-book all session in the period with the correct booker eid (allow not continuous)
CREATE OR REPLACE PROCEDURE unbook_room(floor INT, room INT, date DATE, start_time INT, end_time INT,
                                        eid_booker INT)
AS
$$
declare
    curr_time int;
begin
    curr_time := start_time;
    while curr_time < end_time
        loop
            delete
            from sessions S
            where S.eid_booker = unbook_room.eid_booker
              and S.time = curr_time
              and S.date = unbook_room.date
              and S.floor = unbook_room.floor
              and S.room = unbook_room.room;
            curr_time := curr_time + 1;
        end loop;
end;
$$ language plpgsql;

-- allow join all session in the meeting room during the period ( not allow if cannot join all ,i.e not continuous)
-- if approved cannot join and abort
CREATE OR REPLACE PROCEDURE join_meeting(floor INT, room INT, date DATE, start_time INT, end_time INT, eid INT)
AS
$$
declare
    curr_time        int;
    sessions_existed int;
    fever            boolean;
    is_resigned      boolean;
    is_eligible      boolean;
begin
    curr_time := start_time;
    sessions_existed := (SELECT count(*)
                         FROM sessions S
                         WHERE S.date = join_meeting.date
                           AND S.room = join_meeting.room
                           AND S.floor = join_meeting.floor
                           -- check if the session has been approved
                           AND S.eid_manager is null
                           AND (S.time >= start_time AND S.time < end_time));
    -- get the most updated fever status
    fever := (SELECT fever FROM healthdeclaration HD WHERE HD.eid = join_meeting.eid ORDER BY HD.date DESC LIMIT 1);
    -- check if the employee resign yet
    is_resigned := (SELECT resignedDate FROM employees E WHERE E.eid = join_meeting.eid) is not null;
    is_eligible := not (fever) and not (is_resigned);
    if sessions_existed = end_time - start_time and is_eligible then
        while curr_time < end_time
            loop
                INSERT INTO joins(eid, date, time, room, floor)
                VALUES (eid, date, curr_time, room, floor);
                curr_time := curr_time + 1;
            end loop;
    end if;

end;
$$
    LANGUAGE plpgsql;

-- remove employee from all meeting session ( allow not continuous)
CREATE OR REPLACE PROCEDURE leave_meeting(floor INT, room INT, date DATE, start_time INT, end_time INT, eid INT)
AS
$$
declare
    curr_time   int;
    is_approved boolean;
begin
    curr_time := start_time;
    while curr_time < end_time
        loop
            is_approved := (select eid_manager
                            from sessions S
                            where S.floor = leave_meeting.floor
                              and S.room = leave_meeting.room
                              and S.date = leave_meeting.date
                              and S.time = curr_time) is not null;
            if not is_approved then
                delete
                from joins J
                where J.floor = leave_meeting.floor
                  and J.room = leave_meeting.room
                  and J.date = leave_meeting.date
                  and J.eid = leave_meeting.eid
                  and J.time = curr_time;
            end if;
            curr_time := curr_time + 1;
        end loop;
end;
$$
    language plpgsql;

-- approve all meeting sessions within the same department (ignore all that is not from same department)
-- allow not continuous approval
CREATE OR REPLACE PROCEDURE approve_meeting(floor INT, room INT, date DATE, start_time INT, end_time INT, eid INT)
AS
$$
declare
    curr_time          int;
    booker_department  int;
    manager_department int;
begin
    curr_time := start_time;
    manager_department := (SELECT did FROM employees E WHERE E.eid = approve_meeting.eid);
    while curr_time < end_time
        loop
            booker_department := (SELECT did
                                  FROM employees E
                                           JOIN sessions S
                                                on E.eid = S.eid_booker
                                  WHERE S.floor = approve_meeting.floor
                                    AND S.room = approve_meeting.room
                                    AND S.date = approve_meeting.date
                                    AND S.time = curr_time
            );
            if booker_department = manager_department then
                update sessions S
                set eid_manager = eid
                where S.floor = approve_meeting.floor
                  AND S.room = approve_meeting.room
                  AND S.date = approve_meeting.date
                  AND S.time = curr_time;
            end if;
            curr_time := curr_time + 1;
        end loop;
end;
$$ language plpgsql;

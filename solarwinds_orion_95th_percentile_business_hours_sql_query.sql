-- This is a query to calculate 95th percentile statistics for bits in, bits out
-- and a new column that is the max of bits in vs. bits out for each sample
-- only for business hours (ie excluding weekends and hours before / after work
-- hours
-- 
-- Developed/tested with
--  Microsoft SQL server 2014
--  Orion Platform 2017.1, NPM 12.1

-- Issues
--  You currently must adjust the timezone setting manually and be sure to query
--      only devices that are all in the same timezone
--  Surely performance can be improved

-- To Do
--  Document adding a custom column with a UTC offset for each device and modify
--      this query to use that value instead
--  Account for standard vs. daylight savings time

DECLARE @SampleOffset Float
DECLARE @TargetDeviceOffset Float
DECLARE @TargetPercentile Float
DECLARE @StartBusinessHours Float
DECLARE @EndBusinessHours Float

-- The UTC offset of the timezone the samples are stored in 
-- (ie where the database is)
SET @SampleOffset = -4.0

-- The UTC offset of the timezone where the target devices are
SET @TargetDeviceOffset = -4.0

-- Target percentile as a decimal
SET @TargetPercentile = 0.95

-- When do business hours start ( 0700 = 7am )
SET @StartBusinessHours = 7

-- When do business hours end ( 1800 = 6pm )
SET @EndBusinessHours = 18
;


WITH 
	InterfaceTraffic_Detail_BusinessHours AS (
		-- Create a CTE showing only business hours data
		-- Also adding a MaxBps column
		SELECT
			 i.DateTime
			 ,i.interfaceid
			 ,i.[In_Maxbps]
			 ,i.[out_Maxbps]
			,MaxBps = 
					CASE
						--Use whichever is greater of IN vs. OUT
						WHEN Out_Maxbps > In_Maxbps THEN Out_Maxbps 
						ELSE In_Maxbps 
					END
			
		FROM 
			[swnpm].[dbo].[InterfaceTraffic_Detail] as I
			INNER JOIN [swnpm].[dbo].[Nodes]  as N
				ON (n.NodeID = [i].NodeID )

		WHERE 
			(n.SysName LIKE '%pattern1%'
            -- or n.SysName LIKE '%pattern1%'
			-- or n.SysName LIKE '%pattern2%'
			-- or n.SysName LIKE '%pattern3%'
			-- or n.SysName LIKE '%pattern4%'
			)
			AND
			(
			--	This adjusts for both the timezone of the samples and the target device
			-- Not Saturday or Sunday after adjusting for timezones
			(DATEPART(dw,DATEADD(hh,-@SampleOffset+@TargetDeviceOffset,DateTime)) <> 1 AND (DATEPART(dw,DATEADD(hh,-@SampleOffset+@TargetDeviceOffset,DateTime)) <> 7) )
				AND 
			-- Between @StartBusinessHours and @EndBusinessHours after adjusting for timezones
			(DATEPART(Hour,DATEADD(hh,-@SampleOffset+@TargetDeviceOffset,DateTime)) >= @StartBusinessHours AND (DATEPART(Hour,DATEADD(hh,-@SampleOffset+@TargetDeviceOffset,DateTime)) <= @EndBusinessHours))
			)

		)
, 
	Percentile_IN as (
		-- A CTE that builds on InterfaceTraffic_Detail_BusinessHours for calculating 
		-- the chosen percentile value for each interfaceId
		SELECT
		  t.InterfaceID,
		  -- The smallest value in the chosen percentile
		  -- http://www.dummies.com/education/math/statistics/how-to-calculate-percentiles-in-statistics/
		  Min(CASE
			WHEN seqnum >= @TargetPercentile * cnt
			  THEN
				[In_Maxbps]
		  END) AS percentile
		FROM (
			SELECT
			  t.*,
			  ROW_NUMBER() OVER (PARTITION BY t.InterfaceID ORDER BY [In_Maxbps]) AS seqnum,
			  COUNT(*) OVER (PARTITION BY t.InterfaceID) AS cnt
			FROM InterfaceTraffic_Detail_BusinessHours t
			) t
		GROUP BY t.InterfaceID
		)
, 
	Percentile_out as (
		-- A CTE that builds on InterfaceTraffic_Detail_BusinessHours for calculating 
		-- the chosen percentile value for each interfaceId
		SELECT
		  o.InterfaceID,
		  -- The smallest value in the chosen percentile
		  -- http://www.dummies.com/education/math/statistics/how-to-calculate-percentiles-in-statistics/
		  Min(CASE
			WHEN seqnum >= @TargetPercentile * cnt
			  THEN
				[out_Maxbps]
		  END) AS percentile
		FROM (
			SELECT
			  o.*,
			  ROW_NUMBER() OVER (PARTITION BY o.InterfaceID ORDER BY [Out_Maxbps]) AS seqnum,
			  COUNT(*) OVER (PARTITION BY o.InterfaceID) AS cnt
			FROM InterfaceTraffic_Detail_BusinessHours o
			) o
		GROUP BY o.InterfaceID
)
	,Percentile_max as (
		-- A CTE that builds on InterfaceTraffic_Detail_BusinessHours for calculating 
		-- the chosen percentile value for each interfaceId
		SELECT
		  m.InterfaceID,
		  -- The smallest value in the chosen percentile
		  -- http://www.dummies.com/education/math/statistics/how-to-calculate-percentiles-in-statistics/
		  Min(CASE
			WHEN seqnum >= @TargetPercentile * cnt
			  THEN
				MaxBps
		  END) AS percentile
		FROM (
			SELECT
			  m.*,
			  ROW_NUMBER() OVER (PARTITION BY m.InterfaceID ORDER BY MaxBps) AS seqnum,
			  COUNT(*) OVER (PARTITION BY m.InterfaceID) AS cnt
			FROM InterfaceTraffic_Detail_BusinessHours m
			) m
		GROUP BY m.InterfaceID
)
SELECT 
    Nodes.NodeID
    ,Interfaces.InterfaceId
    ,Nodes.SysName
    ,Interfaces.Caption AS Interface_Caption
    ,InterfaceSpeed
    ,Percentile_in.percentile  AS in_percentile
    ,Percentile_out.percentile AS out_percentile
    ,Percentile_max.percentile AS max_percentile
    , UTC_offset = @TargetDeviceOffset
    , SYSDATETIMEOFFSET () as Date
		
FROM [swnpm].[dbo].[Nodes]
    INNER JOIN [swnpm].[dbo].[Interfaces] 
        ON (Nodes.NodeID = Interfaces.NodeID )
    INNER JOIN Percentile_in
        ON (Interfaces.InterfaceId = Percentile_in.InterfaceId) 
    INNER JOIN Percentile_out
        ON (Interfaces.InterfaceId = Percentile_out.InterfaceId) 
    INNER JOIN Percentile_max
        ON (Interfaces.InterfaceId = Percentile_max.InterfaceId) 

ORDER BY
    SysName, Interface_Caption



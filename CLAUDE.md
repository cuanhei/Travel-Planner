# Travel Planner Trip Planning and Stop Scheduling Flow

## 1. Purpose

This document defines the complete flow used by the travel planner to:

- Create a trip.
- Collect accommodation and selected places.
- Retrieve place information.
- Validate opening hours and operating days.
- Consider weather for individual trip days that fall within the available 7-day forecast period.
- Use the Routes API to calculate actual transportation time between places.
- Assign stops to suitable days.
- Optimize the visiting order for each day.
- Schedule restaurants and hotel buffets at reasonable meal times.
- Recommend nearby places from the Places API when a day has sufficient remaining time.
- Re-optimize the affected day whenever a stop is added or moved.
- Generate the final daily itinerary.

The planner is a **constraint-based scheduling and route optimization system**. It does not simply sort places by shortest distance.

---

# 2. Main Data Required

## 2.1 Trip Information

The user provides:

- Trip name.
- Start date.
- End date.
- Daily start time.
- Daily end time.
- Starting location.
- Preferred transportation mode.
- Selected places.
- Accommodation information, if applicable.

Example:

```text
Trip Name: Kuala Lumpur Trip
Start Date: 10 September 2026
End Date: 12 September 2026
Daily Start Time: 9:00 AM
Daily End Time: 8:00 PM
Transport Mode: Driving
```

---

# 3. Create Trip Days

Calculate all dates between the trip start date and end date.

Example:

```text
Trip:
10 Sep - 12 Sep

Day 1 -> 10 Sep
Day 2 -> 11 Sep
Day 3 -> 12 Sep
```

Each trip day stores:

```text
date
dailyStartTime
dailyEndTime
remainingMinutes
assignedStops
startAnchor
endAnchor
weatherAvailable
weatherForecast
```

---

# 4. Accommodation Handling

Accommodation should be handled separately from normal places to visit.

The user can choose:

```text
1. Add my accommodation
2. Recommend accommodation
3. I do not need accommodation planning
```

## 4.1 Accommodation Nights

The number of normal overnight stays is:

```text
numberOfNights = endDate - startDate
```

Example:

```text
10 Sep - 12 Sep
3 trip days
2 nights
```

Accommodation can be assigned by night.

Example:

```text
10 Sep night -> Hotel A
11 Sep night -> Hotel B
```

---

# 5. Hotel Category Does Not Automatically Mean Accommodation

A place may have:

```text
category = HOTEL
```

but the purpose must be stored separately.

Recommended field:

```text
visitPurpose
```

Possible values:

```text
ACCOMMODATION
MEAL
ATTRACTION
SHOPPING
TRANSPORT
OTHER
```

Example:

```text
Grand Hyatt Kuala Lumpur

category = HOTEL
visitPurpose = ACCOMMODATION
```

Another user may select the same hotel because of its buffet:

```text
Grand Hyatt Kuala Lumpur

category = HOTEL
visitPurpose = MEAL
mealType = DINNER
```

Therefore:

```text
Place Category != Visit Purpose
```

A hotel buffet must be treated as a meal stop instead of accommodation.

---

# 6. User Selects Places

The user selects the destinations they want to visit.

Examples:

```text
KLCC
Aquaria KLCC
Pavilion KL
Batu Caves
Zoo Negara
Restaurant A
Hotel Buffet B
```

User-selected places should normally be treated as priority stops.

They should not be silently replaced by automatically recommended places.

---

# 7. Retrieve Place Information

Use the Places API to retrieve information for each selected stop.

Recommended data:

```text
placeId
displayName
latitude
longitude
primaryType
businessStatus
regularOpeningHours
currentOpeningHours
rating
userRatingCount
```

Additional application data should include:

```text
estimatedVisitDuration
visitPurpose
mealType
environmentType
```

---

# 8. Indoor / Outdoor Classification

Every destination should be classified as:

```text
INDOOR
OUTDOOR
MIXED
```

Examples:

```text
Museum -> INDOOR
Shopping Mall -> INDOOR
Aquarium -> INDOOR

Park -> OUTDOOR
Botanical Garden -> OUTDOOR
Zoo -> OUTDOOR

Theme Park -> MIXED / OUTDOOR
Landmark -> MIXED
```

This classification is used only when weather information is available.

---

# 9. Estimated Visit Duration

Every place requires an estimated visit duration.

Example defaults:

```text
Landmark -> 1-2 hours
Museum -> 2 hours
Shopping Mall -> 2-3 hours
Theme Park -> 6-7 hours
Zoo -> 3-4 hours
Cafe -> 30-60 minutes
Lunch -> 60-90 minutes
Dinner -> 60-120 minutes
Buffet -> 90-120 minutes
```

The user may later adjust these durations.

---

# 10. Restaurant and Meal Handling

Meal stops should have:

```text
visitPurpose = MEAL
mealType
estimatedVisitDuration
```

Possible `mealType` values:

```text
BREAKFAST
LUNCH
DINNER
SNACK
FLEXIBLE
```

Example planning windows:

```text
Breakfast -> 07:00 - 10:00
Lunch     -> 11:30 - 14:30
Dinner    -> 18:00 - 21:00
```

These should be configurable planning preferences.

The restaurant's actual opening hours must always take priority.

---

# 11. Validate Every Stop

Before scheduling, validate every selected place for every trip date.

Check:

```text
Is the business operational?
Is the place open on this date?
Is it closed on this weekday?
Is there a special closure?
Does its opening period overlap the user's daily available time?
Can the visit finish before the place closes?
```

Possible result:

```text
VALID
INVALID
VALID_WITH_TIME_RESTRICTION
```

If a place is closed during the entire trip, mark it as:

```text
Unable to Schedule
```

and inform the user.

---

# 12. Weather Availability Must Be Checked Per Trip Day

Do not check whether the **whole trip** is within 7 days.

Instead, check every trip date individually.

For each trip day:

```text
if tripDate is within the weather API's available forecast period:
    weatherAvailable = true
else:
    weatherAvailable = false
```

Example:

```text
Current Date: 3 Sep

Trip:
8 Sep -> Weather available
9 Sep -> Weather available
10 Sep -> Weather available
11 Sep -> Weather unavailable
12 Sep -> Weather unavailable
```

Therefore, a single trip may contain both:

```text
Weather-aware days
and
Normal planning days
```

---

# 13. Retrieve Weather

For every trip day where:

```text
weatherAvailable = true
```

retrieve the weather forecast for the appropriate town or forecast area.

Example:

```text
10 Sep

Morning:
No Rain

Afternoon:
Thunderstorm

Night:
No Rain
```

Days outside the forecast period should not use assumed or fake weather data.

---

# 14. Convert Weather Into Scheduling Suitability

Convert forecast conditions into simple planning suitability.

Example:

```text
No Rain -> GOOD
Cloudy -> GOOD
Rain -> BAD
Haze -> BAD
Thunderstorm -> SEVERE
```

Possible place suitability:

```text
OUTDOOR + GOOD
-> Preferred

OUTDOOR + BAD
-> Poor

OUTDOOR + SEVERE
-> Avoid if possible

INDOOR + GOOD
-> Normal

INDOOR + BAD
-> Preferred

INDOOR + SEVERE
-> Preferred if transportation remains safe
```

Weather should influence scheduling, but should not automatically delete user-selected places.

---

# 15. Weather Is Only Used When Available

For a day where:

```text
weatherAvailable = false
```

the planner ignores the weather constraint.

The day is planned using:

```text
Opening hours
Travel duration
Geographic proximity
Visit duration
Meal timing
Daily capacity
```

---

# 16. Identify Fixed Anchors

Fixed anchors are locations or activities that strongly constrain the schedule.

Examples:

```text
Hotel
Airport
Train station
Bus terminal
Booked attraction
Reserved event
Fixed restaurant reservation
```

Accommodation may define the start and end anchors.

Example:

```text
Day 1

Start:
Trip Start Location

End:
Hotel A
```

```text
Day 2

Start:
Hotel A

End:
Hotel B
```

```text
Day 3

Start:
Hotel B

End:
Trip End Location
```

---

# 17. If No Hotel Is Selected

A hotel is not mandatory.

The planner can use:

```text
User-selected trip start location
Current starting area
Transport terminal
Another selected day anchor
```

Example:

```text
Day 1:
Start Location
    ->
Attractions
    ->
End of Day
```

Accommodation must therefore not be required for the route optimizer to work.

---

# 18. Identify Time-Sensitive Stops

Time-sensitive stops include:

```text
Breakfast
Lunch
Dinner
Hotel buffet
Booked attraction
Event
Reservation
```

These should receive higher scheduling priority than flexible attractions.

---

# 19. Identify Long-Duration Attractions

Long-duration attractions should be assigned before small flexible attractions.

Example:

```text
Sunway Lagoon -> 6-7 hours
Large Zoo -> 4 hours
Museum -> 2 hours
Landmark -> 1 hour
```

This prevents the planner from filling a day with small stops and later discovering that a large attraction cannot fit.

---

# 20. Use Routes API for Transportation Time

Do not use straight-line distance as the main transportation estimate.

Use the Routes API to calculate actual travel duration.

For example:

```text
Origin:
KLCC

Destination:
Pavilion KL

Travel Mode:
DRIVE
```

Possible result:

```text
distance = 2200 metres
duration = 480 seconds
```

Therefore:

```text
Travel Time = 8 minutes
```

---

# 21. Create the Travel-Time Matrix

Calculate transportation time between relevant pairs of stops.

Example:

| From / To | KLCC | Pavilion | Zoo | Aquaria |
|---|---:|---:|---:|---:|
| KLCC | - | 8 min | 32 min | 5 min |
| Pavilion | 8 min | - | 34 min | 10 min |
| Zoo | 32 min | 34 min | - | 30 min |
| Aquaria | 5 min | 10 min | 30 min | - |

The matrix is used for:

```text
Geographical clustering
Day assignment
Route optimization
Remaining-time calculation
Nearby recommendation validation
```

---

# 22. Create Geographic Clusters

Group places based on Routes API transportation time.

Example guideline:

```text
Travel time <= 30 min
-> Strong same-day candidate

30-60 min
-> Acceptable

60-90 min
-> Poor candidate

> 90 min
-> Avoid normal same-day grouping
```

Places should not be grouped by category.

They should be grouped by practical transportation time.

---

# 23. Determine Valid Days for Every Stop

For every stop, evaluate every trip day.

Check:

```text
Open on that date?
Enough available time?
Reasonable travel distance?
Opening hours fit?
Meal time fits?
Weather suitable if weather is available?
```

Example:

```text
Botanical Garden

Day 1:
Open
Good weather
Nearby
-> Excellent

Day 2:
Open
Thunderstorm
-> Poor

Day 3:
Open
Weather unavailable
-> Normal
```

---

# 24. Day Assignment Score

Each stop can be assigned using a score.

Example:

```text
DayAssignmentScore =
    GeographicTravelPenalty
  + CapacityPenalty
  + ClosedDatePenalty
  + OpeningHourPenalty
  + MealTimePenalty
  + WeatherPenalty
```

Important:

```text
WeatherPenalty = 0
```

when weather is unavailable for that date.

Lower score means the day is more suitable.

---

# 25. Weather-Aware Day Assignment

Example places:

```text
Botanical Garden -> OUTDOOR
Zoo Negara -> OUTDOOR
Aquaria -> INDOOR
Museum -> INDOOR
```

Weather:

```text
Day 1 -> Good
Day 2 -> Thunderstorm
Day 3 -> Weather unavailable
```

Preferred assignment:

```text
DAY 1
Zoo Negara
Botanical Garden

DAY 2
Aquaria
Museum

DAY 3
Normal optimization
```

Weather should not override geographical feasibility.

Do not move a place to a very distant city simply because the weather is better there.

---

# 26. Check Daily Capacity

For each day:

```text
TotalDayDuration =
    TotalVisitDuration
  + TotalRoutesAPITravelDuration
  + TotalWaitingTime
  + TotalMealDuration
```

Ensure:

```text
TotalDayDuration <= DailyAvailableDuration
```

Example:

```text
Daily Time:
9:00 AM - 8:00 PM
= 11 hours

Visits:
7 hours

Transportation:
1 hour

Waiting:
30 minutes

Total:
8.5 hours

Result:
Fits
```

---

# 27. Optimize Stop Order Inside Each Day

After stops are assigned to a day, optimize the visiting order.

Do not simply use the closest next location.

Use a score such as:

```text
NextStopScore =
    RoutesAPITravelTime
  + WaitingTime
  + OpeningHourPenalty
  + ClosingRiskPenalty
  + MealTimePenalty
  + WeatherTimePenalty
```

`WeatherTimePenalty` is only used when weather data exists.

Choose the next stop with the lowest valid score.

---

# 28. Calculate Exact Arrival Time

For each stop:

```text
ArrivalTime =
PreviousStopDepartureTime
+
RoutesAPITravelDuration
```

Example:

```text
Leave Hotel:
9:00 AM

Routes API Travel:
20 minutes

Arrive KLCC:
9:20 AM
```

---

# 29. Check Opening Time

If the user arrives before opening:

```text
VisitStart =
max(ArrivalTime, OpeningTime)
```

Example:

```text
Arrival:
9:20 AM

Opening:
10:00 AM

Waiting:
40 minutes

Visit Start:
10:00 AM
```

If another nearby attraction is already open, the optimizer may choose that place first instead.

---

# 30. Check Closing Time

Calculate:

```text
ExpectedDeparture =
VisitStart
+
VisitDuration
```

Ensure:

```text
ExpectedDeparture <= ClosingTime
```

Example:

```text
Arrival:
4:30 PM

Visit Duration:
2 hours

Closing:
6:00 PM

Expected Finish:
6:30 PM

Result:
Invalid
```

The planner should:

```text
Try another visiting order
or
Move the stop to another day
```

---

# 31. Schedule Reasonable Meal Times

Meal stops should be fitted into preferred windows.

Example lunch:

```text
Preferred:
12:30 PM

Allowed:
11:30 AM - 2:30 PM
```

Possible penalty:

```text
12:30 PM -> 0 penalty
1:00 PM -> very small penalty
2:15 PM -> higher penalty
4:00 PM -> invalid / very high penalty
```

This allows the planner to optimize the route while still producing reasonable eating times.

---

# 32. Time-of-Day Weather Planning

If weather forecast periods are available, the planner can also rearrange stops within the same day.

Example:

```text
Morning:
No Rain

Afternoon:
Thunderstorm
```

Places:

```text
Park -> OUTDOOR
Aquaria -> INDOOR
```

Preferred schedule:

```text
9:00 AM - 11:00 AM
Park

11:30 AM - 1:00 PM
Lunch

1:30 PM - 3:30 PM
Aquaria
```

This is better than placing the outdoor stop during the thunderstorm period.

---

# 33. Check Daily End Time

After adding every stop:

```text
ExpectedDayFinish <= DailyEndTime
```

Example:

```text
Daily End:
8:00 PM

Expected Finish:
7:30 PM
-> Valid
```

```text
Expected Finish:
9:15 PM
-> Invalid
```

If invalid, move one or more flexible stops to another suitable day.

---

# 34. Re-Optimize After Moving a Stop

Whenever a stop moves:

```text
Re-run route optimization
```

Example:

Original:

```text
A -> B -> C -> D
```

D cannot fit.

Move D to Day 2.

Do not automatically keep:

```text
A -> B -> C
```

The better route might now be:

```text
A -> C -> B
```

Therefore, the affected day must always be re-optimized.

---

# 35. Core Schedule Is Completed First

The user's selected stops should be scheduled first.

Only after the core schedule is valid should the system search for optional nearby recommended places.

---

# 36. Calculate Remaining Time for Every Day

Example:

```text
Daily End Time:
8:00 PM

Last Scheduled Stop Ends:
5:00 PM

Remaining Time:
3 hours
```

However, the entire 3 hours cannot automatically be used for another attraction.

The planner must also consider:

```text
Travel to recommended place
Visit duration
Travel to the day's final anchor, if required
```

---

# 37. Determine Whether There Is Enough Time for a Recommendation

Set a configurable minimum.

Example:

```text
Minimum useful remaining time:
90 minutes
```

Then:

```text
Remaining:
30 minutes

Result:
Do not search for another attraction
```

```text
Remaining:
3 hours

Result:
Search for nearby places
```

---

# 38. Search Nearby the Last Scheduled Stop

Use the Places API Nearby Search.

The search center should be:

```text
latitude = lastScheduledStop.latitude
longitude = lastScheduledStop.longitude
```

Example:

```text
Last Stop:
Pavilion KL

Nearby Search:
Around Pavilion KL
```

The recommendation search should focus on places close to the current end of the day's route.

---

# 39. Retrieve Nearby Candidate Places

Possible Places API results:

```text
Aquaria
Petrosains
Museum
Cafe
Shopping Mall
Nearby Attraction
```

Do not automatically add the first result.

---

# 40. Filter Nearby Candidates

For every candidate, check:

```text
Already selected?
Already scheduled?
Business operational?
Open at the expected arrival time?
Visit duration fits?
Can finish before closing?
Weather suitable if available?
Enough time to reach the final day anchor?
```

Remove candidates that fail the required constraints.

---

# 41. Apply Weather to Nearby Recommendations

If weather is available for that day:

```text
Bad Weather + Outdoor Candidate
-> Lower priority or remove

Bad Weather + Indoor Candidate
-> Prefer
```

Example:

```text
Rain expected

Candidate A:
Indoor Museum
-> Preferred

Candidate B:
Outdoor Park
-> Poor
```

If weather is unavailable:

```text
Ignore weather
```

---

# 42. Use Routes API to Check the Candidate

A place being geographically nearby does not guarantee that it is quick to reach.

For every candidate calculate:

```text
LastScheduledStop
->
Routes API
->
Candidate
```

Example:

```text
Candidate A:
500 m away
Travel Time = 18 min

Candidate B:
1.2 km away
Travel Time = 7 min
```

Candidate B may be more suitable despite being farther away by straight-line distance.

---

# 43. Check Whether the Candidate Fits

Example:

```text
Last Stop Ends:
5:00 PM

Travel to Candidate:
10 minutes

Arrival:
5:10 PM

Visit:
1 hour 30 minutes

Finish:
6:40 PM

Daily End:
8:00 PM
```

Result:

```text
Candidate fits
```

---

# 44. Include Travel to the Final Anchor

If the day must end at a hotel or another fixed location, also calculate:

```text
Candidate
->
Routes API
->
Day End Anchor
```

Example:

```text
Candidate Finish:
6:40 PM

Candidate -> Hotel:
30 minutes

Hotel Arrival:
7:10 PM

Daily End:
8:00 PM

Result:
Valid
```

---

# 45. Rank Nearby Recommended Places

No AI is required.

Use a deterministic recommendation score.

Example:

```text
RecommendationScore =
    RouteTravelTime
  + OpeningHourPenalty
  + TimeFitPenalty
  + WeatherPenalty
  + RatingPenalty
```

Lower score means the candidate is more suitable.

The application may show the top 3-5 valid places.

---

# 46. User Chooses Whether to Add the Recommended Place

Recommended places are optional.

Example UI:

```text
You have 2 hr 40 min available.

Nearby Recommendation

Aquaria KLCC
Indoor
Rating: 4.5
Travel: 8 min
Suggested Visit: 1.5 hr
Open
Fits before 8 PM

[Add to Day 1]
```

The system should not automatically insert the place without the user's choice.

---

# 47. Re-Optimize After Adding a Recommendation

Even though the recommendation was searched near the last stop, adding it may change the best route.

Original:

```text
KLCC
->
Pavilion
->
Recommended Place
```

After re-optimization:

```text
KLCC
->
Recommended Place
->
Pavilion
```

may be faster.

Therefore:

```text
Add Candidate
->
Re-run Routes API calculations
->
Re-optimize affected day
```

---

# 48. Final Full-Itinerary Validation

After all scheduling and optional additions are completed, validate the entire itinerary.

Check:

```text
No stop is scheduled while closed.
No stop is scheduled on a closure date.
No visit finishes after closing time.
No day exceeds the user's daily end time.
No duplicate stop exists.
No impossible transportation duration exists.
No unreasonable same-day intercity travel exists.
Meal times are reasonable.
Accommodation anchors are respected.
Weather-aware days use weather appropriately.
No weather is assumed when forecast data is unavailable.
```

---

# 49. Handle Unscheduled Stops

Sometimes all selected places cannot fit.

Do not force them into the itinerary.

Example:

```text
Selected:
10 places

Scheduled:
8 places

Unable to Fit:
2 places
```

Allow the user to:

```text
Remove another stop
Extend the trip
Reduce visit duration
Move a stop manually
Replace a destination
```

---

# 50. Generate Final Daily Schedule

Example:

```text
DAY 1 - 10 September

09:00
Leave Hotel

09:00 - 09:20
Travel

09:20 - 11:20
Batu Caves

11:20 - 11:45
Travel

11:45 - 13:00
Lunch

13:00 - 13:15
Travel

13:15 - 15:15
KLCC

15:15 - 15:25
Travel

15:25 - 17:25
Aquaria KLCC

17:25 - 18:00
Travel

18:00
Return to Hotel
```

For weather-aware days, the UI may also show:

```text
Weather:
Morning - Good
Afternoon - Rain

Outdoor stops were scheduled earlier because rain is expected later.
```

---

# 51. Complete Planning Flow

```text
USER CREATES TRIP
        |
        v
Enter dates + daily start/end time
        |
        v
Create all trip days
        |
        v
Select accommodation / no accommodation
        |
        v
Select places to visit
        |
        v
Determine visit purpose
        |
        v
Identify meal stops
        |
        v
Retrieve Places API information
        |
        v
Classify Indoor / Outdoor / Mixed
        |
        v
Set estimated visit durations
        |
        v
Validate opening days / opening hours
        |
        v
FOR EACH TRIP DAY
        |
        v
Is weather forecast available for this date?
        |
     +--+--+
     |     |
    YES    NO
     |     |
     v     v
Get       Ignore
Weather   Weather
     |     |
     +--+--+
        |
        v
Identify fixed anchors
        |
        v
Identify meal / time-sensitive stops
        |
        v
Identify long-duration attractions
        |
        v
Use Routes API to calculate travel times
        |
        v
Build travel-time matrix
        |
        v
Create geographic clusters
        |
        v
Determine valid days for each stop
        |
        v
Apply:
- opening constraints
- daily capacity
- geographic suitability
- meal timing
- weather when available
        |
        v
Assign stops to suitable days
        |
        v
Prefer outdoor stops during good weather
        |
        v
Prefer indoor stops during bad weather
        |
        v
Check daily capacity
        |
        v
Optimize visiting order
        |
        v
Use Routes API travel duration
        |
        v
Calculate arrival time
        |
        v
Check opening time
        |
        v
Check closing time
        |
        v
Check meal timing
        |
        v
Check time-of-day weather when available
        |
        v
Calculate departure time
        |
        v
Calculate route to next stop
        |
        v
Check daily end time
        |
        v
Conflict?
     +--+--+
     |     |
    YES    NO
     |     |
     v     |
Move Stop |
     |     |
     v     |
Re-optimize
     |     |
     +--+--+
        |
        v
CORE SCHEDULE COMPLETE
        |
        v
Calculate remaining time for each day
        |
        v
Enough useful remaining time?
     +--+--+
     |     |
    YES    NO
     |     |
     v     v
Places   Finish
API      Day
Nearby
Search
     |
     v
Search around LAST scheduled stop
     |
     v
Retrieve nearby candidates
     |
     v
Filter:
- duplicate
- closed
- non-operational
- insufficient time
- unsuitable weather
     |
     v
Use Routes API:
Last Stop -> Candidate
     |
     v
Check:
Travel + Visit + Final Anchor Travel
fits remaining time?
     |
     v
Rank valid candidates
     |
     v
Show recommended places
     |
     v
User adds place?
     |
   +-+-+
   |   |
  YES  NO
   |   |
   v   |
Add   |
Stop  |
   |   |
   v   |
Re-optimize
   |   |
   +-+-+
     |
     v
Validate entire itinerary
     |
     v
GENERATE FINAL SCHEDULE
```

---

# 52. Main System Responsibilities

## Places API

Used for:

```text
Place search
Place details
Coordinates
Category / primary type
Opening hours
Business status
Ratings
Nearby place recommendations
```

---

## Routes API

Used for:

```text
Actual transportation duration
Actual route distance
Travel-time matrix
Stop-to-stop route calculations
Nearby candidate travel validation
Daily route optimization input
```

---

## Weather API

Used only when weather data is available for an individual trip day.

Used for:

```text
Outdoor / indoor suitability
Day assignment
Time-of-day stop ordering
Nearby recommendation filtering
```

---

## Scheduling Algorithm

Responsible for combining:

```text
Trip dates
Daily start/end time
Opening hours
Closed days
Visit duration
Routes API travel duration
Meal timing
Accommodation anchors
Geographical proximity
Weather when available
Remaining daily capacity
```

to produce the final itinerary.

---

# 53. Core Optimization Objective

The overall objective is:

```text
Minimize unnecessary travel time
while maximizing feasible use of the user's available trip time
```

subject to:

```text
Trip dates
Daily start time
Daily end time
Place opening hours
Closed weekdays
Special closure dates
Estimated visit duration
Routes API transportation duration
Meal-time constraints
Accommodation / fixed anchors
Geographic proximity
Weather suitability when forecast data is available
```

The final planner should always prioritize producing a **feasible and realistic itinerary** over forcing every selected stop into the schedule.

# Calculate 95th percentile values for business hours only in Solarwinds Orion
This is a query to calculate 95th percentile statistics for bits in, bits out
and a new column that is the max of bits in vs. bits out for each sample
only for business hours (ie excluding weekends and hours before / after work
hours
 
Developed/tested with
  Microsoft SQL server 2014
  Orion Platform 2017.1, NPM 12.1

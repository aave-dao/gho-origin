#!/usr/bin/env python3
"""
Precision Loss Analysis for sGHO

This script calculates the precision loss between linear approximation and true continuous compounding
using high-precision mathematical operations. It validates the claims made in PRECISION.md.
"""

import math
import decimal
from decimal import Decimal
from typing import List, Tuple

# Set precision for decimal calculations
decimal.getcontext().prec = 50

# Constants
RAY = Decimal('1e27')  # 1e27 precision
DAYS_IN_YEAR = Decimal('365')
SECONDS_IN_YEAR = Decimal('31536000')  # 365 * 24 * 3600

def calculate_linear_growth_factor(rate_bps: int, time_seconds: int) -> Decimal:
    """
    Calculate linear approximation growth factor: 1 + rate * time
    
    Args:
        rate_bps: Annual rate in basis points (e.g., 1000 = 10%)
        time_seconds: Time period in seconds
    
    Returns:
        Linear growth factor
    """
    # Convert rate from basis points to decimal
    rate_decimal = Decimal(rate_bps) / Decimal('10000')
    
    # Calculate rate per second
    rate_per_second = rate_decimal / SECONDS_IN_YEAR
    
    # Linear approximation: 1 + rate * time
    growth_factor = Decimal('1') + (rate_per_second * Decimal(str(time_seconds)))
    
    return growth_factor

def calculate_continuous_compounding_factor(rate_bps: int, time_seconds: int) -> Decimal:
    """
    Calculate true continuous compounding growth factor: e^(rate * time)
    
    Args:
        rate_bps: Annual rate in basis points (e.g., 1000 = 10%)
        time_seconds: Time period in seconds
    
    Returns:
        Continuous compounding growth factor
    """
    # Convert rate from basis points to decimal
    rate_decimal = Decimal(rate_bps) / Decimal('10000')
    
    # Calculate rate per second
    rate_per_second = rate_decimal / SECONDS_IN_YEAR
    
    # True continuous compounding: e^(rate * time)
    exponent = rate_per_second * Decimal(str(time_seconds))
    growth_factor = Decimal(str(math.exp(float(exponent))))
    
    return growth_factor

def calculate_precision_loss(linear_factor: Decimal, continuous_factor: Decimal) -> Decimal:
    """
    Calculate precision loss as a percentage of the initial value
    
    Args:
        linear_factor: Linear approximation growth factor
        continuous_factor: Continuous compounding growth factor
    
    Returns:
        Precision loss as a percentage of initial value (in basis points)
    """
    if continuous_factor <= linear_factor:
        return Decimal('0')
    
    difference = continuous_factor - linear_factor
    precision_loss = (difference / Decimal('1')) * Decimal('10000')  # Convert to basis points relative to initial value
    
    return precision_loss

def analyze_contract_rate_per_second_calculation():
    """
    Analyze the precision loss in the contract's rate per second calculation
    This mimics the exact calculation in setTargetRate()
    """
    print("=== Contract Rate Per Second Calculation Analysis ===")
    print()
    
    rates_to_test = [100, 500, 1000, 2000, 3000, 4000, 5000]  # 1% to 50% APR
    
    print("| Rate (bps) | APR (%) | Contract Rate Per Second (RAY) | Exact Rate Per Second (RAY) | Precision Loss (bps) |")
    print("|------------|---------|--------------------------------|----------------------------|---------------------|")
    
    for rate_bps in rates_to_test:
        apr_percent = rate_bps / 100
        
        # Contract calculation (exact as in setTargetRate)
        # annualRateRay = uint256(newRate) * RAY / 10000
        # ratePerSecond = (annualRateRay / 365 days).toUint96()
        contract_annual_rate_ray = Decimal(rate_bps) * RAY / Decimal('10000')
        contract_rate_per_second = contract_annual_rate_ray / SECONDS_IN_YEAR
        
        # Exact calculation with full precision
        exact_rate_per_second = (Decimal(rate_bps) / Decimal('10000')) / SECONDS_IN_YEAR * RAY
        
        # Calculate precision loss
        precision_loss = abs(exact_rate_per_second - contract_rate_per_second) / RAY * Decimal('10000')
        
        print(f"| {rate_bps:10} | {apr_percent:7.1f} | {contract_rate_per_second:32.0f} | {exact_rate_per_second:28.0f} | {precision_loss:19.20f} |")
    
    print()

def analyze_yield_index_update_precision():
    """
    Analyze precision loss in yield index updates for different scenarios
    This mimics the exact calculation in _getCurrentYieldIndex()
    """
    print("=== Yield Index Update Precision Analysis ===")
    print()
    
    # Test scenarios: different rates and time periods
    scenarios = [
        (100, 3600, "1% APR, 1 hour"),
        (1000, 3600, "10% APR, 1 hour"),
        (5000, 3600, "50% APR, 1 hour"),
        (100, 86400, "1% APR, 1 day"),
        (1000, 86400, "10% APR, 1 day"),
        (5000, 86400, "50% APR, 1 day"),
        (100, 604800, "1% APR, 1 week"),
        (1000, 604800, "10% APR, 1 week"),
        (5000, 604800, "50% APR, 1 week"),
    ]
    
    print("| Scenario | Contract Growth Factor | Exact Growth Factor | Precision Loss (bps) |")
    print("|----------|----------------------|-------------------|---------------------|")
    
    for rate_bps, time_seconds, scenario_desc in scenarios:
        # Contract calculation (exact as in _getCurrentYieldIndex)
        # annualRateRay = uint256(targetRate) * RAY / 10000
        # ratePerSecond = annualRateRay / 365 days
        # accumulatedRate = ratePerSecond * timeSinceLastUpdate
        # growthFactor = RAY + accumulatedRate
        
        contract_annual_rate_ray = Decimal(rate_bps) * RAY / Decimal('10000')
        contract_rate_per_second = contract_annual_rate_ray / SECONDS_IN_YEAR
        contract_accumulated_rate = contract_rate_per_second * Decimal(str(time_seconds))
        contract_growth_factor = RAY + contract_accumulated_rate
        
        # Exact calculation with full precision
        exact_rate_per_second = (Decimal(rate_bps) / Decimal('10000')) / SECONDS_IN_YEAR * RAY
        exact_accumulated_rate = exact_rate_per_second * Decimal(str(time_seconds))
        exact_growth_factor = RAY + exact_accumulated_rate
        
        # Calculate precision loss
        precision_loss = abs(exact_growth_factor - contract_growth_factor) / RAY * Decimal('10000')
        
        print(f"| {scenario_desc:20} | {contract_growth_factor:20.0f} | {exact_growth_factor:17.0f} | {precision_loss:19.20f} |")
    
    print()

def analyze_cumulative_yield_index_precision():
    """
    Analyze precision loss when yield index is updated multiple times
    This shows how precision loss accumulates over multiple operations
    """
    print("=== Cumulative Yield Index Precision Analysis ===")
    print()
    
    rate_bps = 1000  # 10% APR
    total_time = 86400  # 1 day
    
    # Different update frequencies
    update_scenarios = [
        (1, "Every second"),
        (60, "Every minute"),
        (3600, "Every hour"),
        (86400, "Once per day"),
    ]
    
    print("| Update Frequency | Updates | Final Contract Index | Final Exact Index | Cumulative Precision Loss (bps) |")
    print("|------------------|---------|---------------------|------------------|--------------------------------|")
    
    for update_interval, interval_desc in update_scenarios:
        updates_count = total_time // update_interval
        
        # Simulate contract behavior with multiple updates
        contract_yield_index = RAY  # Start at 1 RAY
        exact_yield_index = RAY
        
        for _ in range(updates_count):
            # Contract calculation for this update
            contract_annual_rate_ray = Decimal(rate_bps) * RAY / Decimal('10000')
            contract_rate_per_second = contract_annual_rate_ray / SECONDS_IN_YEAR
            contract_accumulated_rate = contract_rate_per_second * Decimal(str(update_interval))
            contract_growth_factor = RAY + contract_accumulated_rate
            contract_yield_index = contract_yield_index * contract_growth_factor / RAY
            
            # Exact calculation for this update
            exact_rate_per_second = (Decimal(rate_bps) / Decimal('10000')) / SECONDS_IN_YEAR * RAY
            exact_accumulated_rate = exact_rate_per_second * Decimal(str(update_interval))
            exact_growth_factor = RAY + exact_accumulated_rate
            exact_yield_index = exact_yield_index * exact_growth_factor / RAY
        
        # Calculate cumulative precision loss
        cumulative_precision_loss = abs(exact_yield_index - contract_yield_index) / RAY * Decimal('10000')
        
        print(f"| {interval_desc:16} | {updates_count:7} | {contract_yield_index:19.0f} | {exact_yield_index:16.0f} | {cumulative_precision_loss:32.20f} |")
    
    print()

def analyze_extreme_yield_index_scenarios():
    """
    Analyze extreme scenarios for yield index precision loss (capped at 1 month)
    """
    print("=== Extreme Yield Index Scenarios (Max 1 Month) ===")
    print()
    
    scenarios = [
        (1000, 2592000, "10% APR for 1 month"),
        (5000, 2592000, "50% APR for 1 month"),
        (1000, 604800, "10% APR for 1 week"),
        (5000, 604800, "50% APR for 1 week"),
        (1000, 86400, "10% APR for 1 day"),
        (5000, 86400, "50% APR for 1 day"),
    ]
    
    print("| Scenario | Contract Final Index | Exact Final Index | Precision Loss (bps) |")
    print("|----------|---------------------|------------------|---------------------|")
    
    for rate_bps, time_seconds, scenario_desc in scenarios:
        # Contract calculation
        contract_annual_rate_ray = Decimal(rate_bps) * RAY / Decimal('10000')
        contract_rate_per_second = contract_annual_rate_ray / SECONDS_IN_YEAR
        contract_accumulated_rate = contract_rate_per_second * Decimal(str(time_seconds))
        contract_growth_factor = RAY + contract_accumulated_rate
        contract_final_index = RAY * contract_growth_factor / RAY
        
        # Exact calculation
        exact_rate_per_second = (Decimal(rate_bps) / Decimal('10000')) / SECONDS_IN_YEAR * RAY
        exact_accumulated_rate = exact_rate_per_second * Decimal(str(time_seconds))
        exact_growth_factor = RAY + exact_accumulated_rate
        exact_final_index = RAY * exact_growth_factor / RAY
        
        # Calculate precision loss
        precision_loss = abs(exact_final_index - contract_final_index) / RAY * Decimal('10000')
        
        print(f"| {scenario_desc:20} | {contract_final_index:19.0f} | {exact_final_index:16.0f} | {precision_loss:19.20f} |")
    
    print()

def analyze_contract_linear_growth_factors():
    """
    Analyze the contract's linear growth factors using actual test data
    This function can be used with the output from test_linear_growth_factors_for_python
    """
    print("=== Contract Linear Growth Factors Analysis ===")
    print()
    
    # Contract growth factors from test output (in RAY units)
    contract_data = [
        # Rate, Period, Growth Factor (RAY units)
        (1000, 1, 1000000003170979198376458650),
        (1000, 60, 1000000190258751902587519000),
        (1000, 3600, 1000011415525114155251140000),
        (1000, 86400, 1000273972602739726027360000),
        (1000, 604800, 1001917808219178082191520000),
        (1000, 2592000, 1008219178082191780820800000),
        (2500, 1, 1000000007927447995941146626),
        (2500, 60, 1000000475646879756468797560),
        (2500, 3600, 1000028538812785388127853600),
        (2500, 86400, 1000684931506849315068486400),
        (2500, 604800, 1004794520547945205479404800),
        (2500, 2592000, 1020547945205479452054592000),
        (5000, 1, 1000000015854895991882293252),
        (5000, 60, 1000000951293759512937595120),
        (5000, 3600, 1000057077625570776255707200),
        (5000, 86400, 1001369863013698630136972800),
        (5000, 604800, 1009589041095890410958809600),
        (5000, 2592000, 1041095890410958904109184000),
    ]
    
    print("| Rate (bps) | Period | Contract Growth Factor | Python Growth Factor | Difference (bps) |")
    print("|------------|--------|----------------------|-------------------|------------------|")
    
    for rate_bps, period_sec, contract_growth_factor_ray in contract_data:
        # Convert contract growth factor to decimal
        contract_growth_factor = Decimal(str(contract_growth_factor_ray)) / RAY
        
        # Calculate Python growth factor
        python_growth_factor = calculate_linear_growth_factor(rate_bps, period_sec)
        
        # Calculate difference in basis points
        difference_bps = abs(contract_growth_factor - python_growth_factor) * Decimal('10000')
        
        # Format period description
        period_desc = {
            1: "1s", 60: "1m", 3600: "1h", 
            86400: "1d", 604800: "1w", 2592000: "1M"
        }.get(period_sec, f"{period_sec}s")
        
        print(f"| {rate_bps:10} | {period_desc:6} | {contract_growth_factor:20.27f} | {python_growth_factor:17.27f} | {difference_bps:16.20f} |")
    
    print()
    
    # Summary statistics
    differences = []
    for rate_bps, period_sec, contract_growth_factor_ray in contract_data:
        contract_growth_factor = Decimal(str(contract_growth_factor_ray)) / RAY
        python_growth_factor = calculate_linear_growth_factor(rate_bps, period_sec)
        difference_bps = abs(contract_growth_factor - python_growth_factor) * Decimal('10000')
        differences.append(difference_bps)
    
    max_diff = max(differences)
    avg_diff = sum(differences) / len(differences)
    
    print(f"Summary:")
    print(f"  Maximum difference: {max_diff:.20f} bps")
    print(f"  Average difference: {avg_diff:.20f} bps")
    print(f"  Total scenarios: {len(differences)}")
    print()

def analyze_precision_loss_10_percent_apr():
    """Analyze precision loss for 10% APR across different time periods (capped at 1 month)"""
    print("=== Precision Loss Analysis: 10% APR (Max 1 Month) ===")
    print()
    
    rate_bps = 1000  # 10% APR
    time_periods = [
        (1, "1 second"),
        (60, "1 minute"),
        (3600, "1 hour"),
        (86400, "1 day"),
        (604800, "1 week"),
        (2592000, "1 month (30 days)")
    ]
    
    for time_seconds, time_desc in time_periods:
        linear_factor = calculate_linear_growth_factor(rate_bps, time_seconds)
        continuous_factor = calculate_continuous_compounding_factor(rate_bps, time_seconds)
        precision_loss = calculate_precision_loss(linear_factor, continuous_factor)
        
        print(f"Time period: {time_desc}")
        print(f"Linear growth factor: {linear_factor:.30f}")
        print(f"Continuous growth factor: {continuous_factor:.30f}")
        print(f"Precision loss (basis points): {precision_loss:.20f}")
        print("-" * 80)

def analyze_precision_loss_max_rate():
    """Analyze precision loss for maximum rate (50% APR) across different time periods (capped at 1 month)"""
    print("=== Precision Loss Analysis: 50% APR (Maximum Rate) - Max 1 Month ===")
    print()
    
    rate_bps = 5000  # 50% APR (MAX_SAFE_RATE)
    time_periods = [
        (1, "1 second"),
        (60, "1 minute"),
        (3600, "1 hour"),
        (86400, "1 day"),
        (604800, "1 week"),
        (2592000, "1 month (30 days)")
    ]
    
    for time_seconds, time_desc in time_periods:
        linear_factor = calculate_linear_growth_factor(rate_bps, time_seconds)
        continuous_factor = calculate_continuous_compounding_factor(rate_bps, time_seconds)
        precision_loss = calculate_precision_loss(linear_factor, continuous_factor)
        
        print(f"Time period: {time_desc}")
        print(f"Linear growth factor: {linear_factor:.30f}")
        print(f"Continuous growth factor: {continuous_factor:.30f}")
        print(f"Precision loss (basis points): {precision_loss:.20f}")
        print("-" * 80)

def analyze_update_frequency_impact():
    """Analyze the impact of update frequency on precision loss"""
    print("=== Update Frequency Impact Analysis ===")
    print()
    
    rate_bps = 1000  # 10% APR
    total_time = 86400  # 1 day
    
    update_intervals = [
        (1, "Every second"),
        (3600, "Every hour"),
        (86400, "Every day"),
        (86400, "Single update")
    ]
    
    for interval, interval_desc in update_intervals:
        # Calculate how many updates would occur
        updates_count = total_time // interval if interval > 0 else 1
        
        # For each update, calculate the growth factor
        # This simulates the actual sGHO behavior where each update uses linear approximation
        cumulative_linear_factor = Decimal('1')
        
        for _ in range(updates_count):
            update_linear_factor = calculate_linear_growth_factor(rate_bps, interval)
            cumulative_linear_factor *= update_linear_factor
        
        # Calculate the theoretical continuous compounding for the entire period
        theoretical_continuous_factor = calculate_continuous_compounding_factor(rate_bps, total_time)
        
        # Calculate precision loss
        precision_loss = calculate_precision_loss(cumulative_linear_factor, theoretical_continuous_factor)
        
        print(f"Update interval: {interval_desc}")
        print(f"Updates performed: {updates_count}")
        print(f"Cumulative linear factor: {cumulative_linear_factor:.30f}")
        print(f"Theoretical continuous factor: {theoretical_continuous_factor:.30f}")
        print(f"Precision loss (basis points): {precision_loss:.20f}")
        print("-" * 80)

def analyze_extreme_scenarios():
    """Analyze extreme scenarios for precision loss (capped at 1 month)"""
    print("=== Extreme Scenarios Analysis (Max 1 Month) ===")
    print()
    
    scenarios = [
        (1000, 2592000, "10% APR for 1 month"),
        (5000, 2592000, "50% APR for 1 month"),
        (1000, 604800, "10% APR for 1 week"),
        (5000, 604800, "50% APR for 1 week"),
        (1000, 86400, "10% APR for 1 day"),
        (5000, 86400, "50% APR for 1 day"),
    ]
    
    for rate_bps, time_seconds, scenario_desc in scenarios:
        linear_factor = calculate_linear_growth_factor(rate_bps, time_seconds)
        continuous_factor = calculate_continuous_compounding_factor(rate_bps, time_seconds)
        precision_loss = calculate_precision_loss(linear_factor, continuous_factor)
        
        print(f"Scenario: {scenario_desc}")
        print(f"Linear growth factor: {linear_factor:.30f}")
        print(f"Continuous growth factor: {continuous_factor:.30f}")
        print(f"Precision loss (basis points): {precision_loss:.20f}")
        print("-" * 80)

def generate_summary_table():
    """Generate a summary table for documentation (capped at 1 month)"""
    print("=== Summary Table for PRECISION.md (Max 1 Month) ===")
    print()
    
    print("| Update Frequency | Time Period | Linear Growth Factor | Continuous Growth Factor | Precision Loss |")
    print("|------------------|-------------|---------------------|-------------------------|----------------|")
    
    rate_bps = 1000  # 10% APR
    time_periods = [
        (1, "1 second"),
        (60, "1 minute"),
        (3600, "1 hour"),
        (86400, "1 day"),
        (604800, "1 week"),
        (2592000, "1 month")
    ]
    
    for time_seconds, time_desc in time_periods:
        linear_factor = calculate_linear_growth_factor(rate_bps, time_seconds)
        continuous_factor = calculate_continuous_compounding_factor(rate_bps, time_seconds)
        precision_loss = calculate_precision_loss(linear_factor, continuous_factor)
        
        print(f"| {time_desc} | {time_seconds} sec | {linear_factor:.27f} | {continuous_factor:.27f} | {precision_loss:.20f}% |")

def main():
    """Main function to run all precision loss analyses"""
    print("sGHO Precision Loss Analysis")
    print("=" * 50)
    print()
    
    # Run contract-specific analyses first
    analyze_contract_rate_per_second_calculation()
    analyze_yield_index_update_precision()
    analyze_cumulative_yield_index_precision()
    analyze_extreme_yield_index_scenarios()
    
    # Run contract linear growth factor analysis
    analyze_contract_linear_growth_factors()
    
    print("\n" + "="*80 + "\n")
    
    # Run original analyses
    analyze_precision_loss_10_percent_apr()
    print()
    
    analyze_precision_loss_max_rate()
    print()
    
    analyze_update_frequency_impact()
    print()
    
    analyze_extreme_scenarios()
    print()
    
    generate_summary_table()
    print()

if __name__ == "__main__":
    main() 
#!/bin/bash

# Script to run tests for redmine_cloud_attachment plugin
# Based on official Redmine Plugin Tutorial documentation

echo "🧪 Running tests for redmine_cloud_attachment plugin..."

# Navigate to Redmine root
cd "$(dirname "$0")/../../.."

# Set test environment
export RAILS_ENV=test

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to run a specific test with error handling
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .rb)
    
    echo -e "${YELLOW}📋 Running $test_name...${NC}"
    
    if bundle exec rake test TEST="$test_file" 2>/dev/null; then
        echo -e "${GREEN}✅ $test_name passed${NC}"
        return 0
    else
        echo -e "${RED}❌ $test_name failed${NC}"
        return 1
    fi
}

# Check if test database is setup
if ! bundle exec rails runner -e test "puts 'Test DB OK'" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️ Test database not setup. Running setup script...${NC}"
    ./plugins/redmine_cloud_attachment/test/setup_test_db.sh
fi

echo -e "${YELLOW}🚀 Starting test execution...${NC}"

# Run individual test files
failed_tests=0
total_tests=0

# Unit tests
for test_file in plugins/redmine_cloud_attachment/test/unit/*.rb; do
    if [ -f "$test_file" ]; then
        total_tests=$((total_tests + 1))
        if ! run_test "$test_file"; then
            failed_tests=$((failed_tests + 1))
        fi
    fi
done

# Integration tests
for test_file in plugins/redmine_cloud_attachment/test/integration/*.rb; do
    if [ -f "$test_file" ]; then
        total_tests=$((total_tests + 1))
        if ! run_test "$test_file"; then
            failed_tests=$((failed_tests + 1))
        fi
    fi
done

# Summary
echo "═══════════════════════════════════════"
if [ $failed_tests -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed! ($total_tests/$total_tests)${NC}"
    exit 0
else
    echo -e "${RED}💥 $failed_tests/$total_tests tests failed${NC}"
    exit 1
fi 

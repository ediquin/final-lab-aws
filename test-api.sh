#!/bin/bash

# File Gateway API Testing Script
# Usage: ./test-api.sh <API_ENDPOINT>

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <API_ENDPOINT>"
    echo "Example: $0 https://abc123.execute-api.us-east-1.amazonaws.com/prod"
    exit 1
fi

API_ENDPOINT=$1
TEST_FILE="test-upload.txt"
DOWNLOAD_FILE="test-download.txt"

echo "======================================"
echo "File Gateway API Test"
echo "======================================"
echo "API Endpoint: $API_ENDPOINT"
echo ""

# Clean up any previous test files
rm -f $TEST_FILE $DOWNLOAD_FILE

# Step 1: Create a test file
echo "Step 1: Creating test file..."
echo "This is a test file for the File Gateway service. Timestamp: $(date)" > $TEST_FILE
echo "✓ Test file created: $TEST_FILE"
echo ""

# Step 2: Request upload URL
echo "Step 2: Requesting upload URL..."
UPLOAD_RESPONSE=$(curl -s -X POST $API_ENDPOINT/files \
  -H "Content-Type: application/json" \
  -d "{\"filename\": \"$TEST_FILE\", \"contentType\": \"text/plain\"}")

echo "Response: $UPLOAD_RESPONSE"
echo ""

# Extract upload URL and object key
UPLOAD_URL=$(echo $UPLOAD_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['uploadUrl'])" 2>/dev/null || echo "")
OBJECT_KEY=$(echo $UPLOAD_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['objectKey'])" 2>/dev/null || echo "")

if [ -z "$UPLOAD_URL" ]; then
    echo "✗ Failed to get upload URL"
    exit 1
fi

echo "✓ Upload URL obtained"
echo "✓ Object Key: $OBJECT_KEY"
echo ""

# Step 3: Upload file to S3
echo "Step 3: Uploading file to S3..."
UPLOAD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$UPLOAD_URL" \
  -H "Content-Type: text/plain" \
  --data-binary "@$TEST_FILE")

if [ "$UPLOAD_STATUS" == "200" ]; then
    echo "✓ File uploaded successfully (HTTP $UPLOAD_STATUS)"
else
    echo "✗ Upload failed (HTTP $UPLOAD_STATUS)"
    exit 1
fi
echo ""

# Step 4: Test redirect behavior
echo "Step 4: Testing download redirect..."
REDIRECT_RESPONSE=$(curl -s -i $API_ENDPOINT/files/$OBJECT_KEY)
echo "$REDIRECT_RESPONSE" | head -n 15
echo ""

if echo "$REDIRECT_RESPONSE" | grep -q "HTTP.*307"; then
    echo "✓ Received 307 Temporary Redirect"
else
    echo "⚠ Did not receive expected 307 status code"
fi

if echo "$REDIRECT_RESPONSE" | grep -qi "location:"; then
    echo "✓ Location header present"
else
    echo "✗ Location header missing"
fi
echo ""

# Step 5: Download file following redirect
echo "Step 5: Downloading file (following redirect)..."
DOWNLOAD_STATUS=$(curl -s -L -o $DOWNLOAD_FILE -w "%{http_code}" $API_ENDPOINT/files/$OBJECT_KEY)

if [ "$DOWNLOAD_STATUS" == "200" ]; then
    echo "✓ File downloaded successfully (HTTP $DOWNLOAD_STATUS)"
else
    echo "✗ Download failed (HTTP $DOWNLOAD_STATUS)"
    exit 1
fi
echo ""

# Step 6: Verify downloaded content
echo "Step 6: Verifying downloaded content..."
if diff $TEST_FILE $DOWNLOAD_FILE > /dev/null; then
    echo "✓ Downloaded file matches original"
else
    echo "✗ Downloaded file differs from original"
    exit 1
fi
echo ""

# Display file contents
echo "File contents:"
cat $DOWNLOAD_FILE
echo ""

echo "======================================"
echo "✓ All tests passed successfully!"
echo "======================================"

# Clean up
rm -f $TEST_FILE $DOWNLOAD_FILE
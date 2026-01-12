import json
import os
import boto3
from botocore.exceptions import ClientError
from urllib.parse import unquote

# Initialize S3 client
s3_client = boto3.client('s3')
BUCKET_NAME = os.environ.get('BUCKET_NAME')

def lambda_handler(event, context):
    """
    Main Lambda handler for File Gateway operations
    Handles both POST (upload preparation) and GET (download) requests
    """
    print(f"Event: {json.dumps(event)}")
    
    http_method = event.get('httpMethod')
    path = event.get('path', '')
    
    try:
        if http_method == 'POST' and path == '/files':
            return handle_upload_preparation(event)
        elif http_method == 'GET' and path.startswith('/files/'):
            return handle_download(event)
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Not found'})
            }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def handle_upload_preparation(event):
    """
    POST /files
    Generates a pre-signed URL for uploading a file directly to S3
    """
    try:
        body = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    
    filename = body.get('filename')
    if not filename:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'filename is required'})
        }
    
    content_type = body.get('contentType', 'application/octet-stream')
    object_key = filename
    
    # Generate pre-signed URL for PUT upload (valid for 15 minutes)
    try:
        upload_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': object_key,
                'ContentType': content_type
            },
            ExpiresIn=900  # 15 minutes
        )
    except ClientError as e:
        print(f"Error generating pre-signed URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Failed to generate upload URL'})
        }
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'objectKey': object_key,
            'uploadUrl': upload_url,
            'method': 'PUT',
            'contentType': content_type,
            'expiresIn': 900
        })
    }

def handle_download(event):
    """
    GET /files/{objectKey}
    Generates a pre-signed download URL and returns an HTTP redirect
    """
    path_parameters = event.get('pathParameters', {})
    object_key = path_parameters.get('objectKey')
    
    if not object_key:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'objectKey is required'})
        }
    
    # URL decode the object key
    object_key = unquote(object_key)
    
    # Check if object exists
    try:
        s3_client.head_object(Bucket=BUCKET_NAME, Key=object_key)
    except ClientError as e:
        if e.response['Error']['Code'] == '404':
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'File not found'})
            }
        else:
            raise
    
    # Generate pre-signed URL for download (valid for 1 hour)
    try:
        download_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': object_key
            },
            ExpiresIn=3600  # 1 hour
        )
    except ClientError as e:
        print(f"Error generating pre-signed URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Failed to generate download URL'})
        }
    
    # Return 307 Temporary Redirect
    return {
        'statusCode': 307,
        'headers': {
            'Location': download_url,
            'Content-Type': 'application/json'
        },
        'body': json.dumps({
            'message': 'Redirecting to download URL',
            'expiresIn': 3600
        })
    }
#!/bin/bash

REGION=%REGION%
S3_BUCKET_IN=%S3BUCKET_IN%
S3_BUCKET_OUT=%S3BUCKET_OUT%
SQSQUEUE=%SQSQUEUE%

while sleep 5; do 

  JSON=$(aws sqs --output=json get-queue-attributes \
    --queue-url $SQSQUEUE \
    --attribute-names ApproximateNumberOfMessages)
  MESSAGES=$(echo "$JSON" | jq -r '.Attributes.ApproximateNumberOfMessages')

  if [ $MESSAGES -eq 0 ]; then

    continue

  fi

  JSON=$(aws sqs --output=json receive-message --queue-url $SQSQUEUE)
  RECEIPT=$(echo "$JSON" | jq -r '.Messages[] | .ReceiptHandle')
  BODY=$(echo "$JSON" | jq -r '.Messages[] | .Body')

  if [ -z "$RECEIPT" ]; then

    logger "$0: Empty receipt. Something went wrong."
    continue

  fi

  logger "$0: Found $MESSAGES messages in $SQSQUEUE. Details: JSON=$JSON, RECEIPT=$RECEIPT, BODY=$BODY"

  INPUT=$(echo "$BODY" | jq -r '.Records[0] | .s3.object.key')
  FNAME=$(echo $INPUT | rev | cut -f2 -d"." | rev | tr '[:upper:]' '[:lower:]')
  FEXT=$(echo $INPUT | rev | cut -f1 -d"." | rev | tr '[:upper:]' '[:lower:]')

  if [ "$FEXT" = "jpg" -o "$FEXT" = "png" -o "$FEXT" = "gif" ]; then

    logger "$0: Found work to convert. Details: INPUT=$INPUT, FNAME=$FNAME, FEXT=$FEXT"

    IN=`aws s3 cp s3://$S3_BUCKET_IN/$INPUT /tmp`
    logger "$0: $IN"
    CONVERT=`convert /tmp/$INPUT /tmp/$FNAME.pdf`
    logger "$0: $CONVERT"
    logger "$0: Convert done. Copying to S3 and cleaning up... Stack: $STACKNAME"

    OUT=`aws s3 cp /tmp/$FNAME.pdf s3://$S3_BUCKET_OUT`
    logger "$0: $OUT"
    rm -f /tmp/$INPUT /tmp/$FNAME.pdf
    CLEAN=`aws s3 rm s3://$S3_BUCKET_IN/$INPUT`
    logger "$0: $CLEAN"
    SQS=`aws sqs --output=json delete-message --queue-url $SQSQUEUE --receipt-handle $RECEIPT`
    logger "$0: $SQS"
  else

    logger "$0: Skipping message - file not of type jpg, png, or gif. Deleting message from queue"

    aws sqs --output=json delete-message --queue-url $SQSQUEUE --receipt-handle $RECEIPT

  fi

done
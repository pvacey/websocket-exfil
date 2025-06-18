# The client runs this follow command to fetch the script
# (Invoke-WebRequest -Uri "<URI_HERE>" -UseBasicParsing -ErrorAction Stop).Content | Invoke-Expression

# Define the WebSocket server URI
$wsUri = "ws://{{ .Host }}/ws" # Ensure this matches your server's address
$payloadFilePath = Read-Host -Prompt "Enter the path to the file you want to send (e.g., payload.txt)"
$payloadFilePath = Join-Path -Path (Get-Location).Path -ChildPath $payloadFilePath
$chunkSize = 100*1024 # Define the chunk size in bytes (e.g., 1KB)

# Create a new ClientWebSocket object
$webSocket = New-Object System.Net.WebSockets.ClientWebSocket
$webSocket.Options.SetRequestHeader("X-User-Agent", "WindowsPowerShell WebSocket") # Optional: Set a custom User-Agent header

# Create a CancellationTokenSource for managing cancellation (good practice for async operations)
$cancellationTokenSource = New-Object System.Threading.CancellationTokenSource
$cancellationToken = $cancellationTokenSource.Token

Write-Host "Connecting to WebSocket server at $wsUri..."

try {
    # Connect to the WebSocket server asynchronously
    $connectTask = $webSocket.ConnectAsync($wsUri, $cancellationToken)
    $connectTask.Wait() # Wait for the connection to complete

    if ($webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        Write-Host "Connected to WebSocket server."

        # --- Read the content of payload.txt as raw bytes ---
        if (-not (Test-Path $payloadFilePath)) {
            Write-Error "Error: Payload file '$payloadFilePath' not found in the current directory."
            return # Exit script if file not found
        }

        # Read the file content as raw bytes directly
        # This is crucial for handling binary files or ensuring exact byte transfer
        $fileBytes = [System.IO.File]::ReadAllBytes($payloadFilePath)
        Write-Host "Read payload from '$payloadFilePath' ($($fileBytes.Length) bytes)."

        # --- Send the payload over WebSocket in chunks ---
        Write-Host "Sending payload over WebSocket in chunks..."

        $startMessage = @{
            filename = $payloadFilePath.Split("\\")[-1]
        } | ConvertTo-Json
        $startBytes = [System.Text.Encoding]::UTF8.GetBytes($startMessage)
        $startBuffer = New-Object System.ArraySegment[byte]($startBytes, 0, $startBytes.Length)
        $startSendTask = $webSocket.SendAsync($startBuffer, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cancellationToken)
        $startSendTask.Wait()

        $totalBytesSent = 0
        while ($totalBytesSent -lt $fileBytes.Length) {
            $bytesRemaining = $fileBytes.Length - $totalBytesSent
            $currentChunkSize = [System.Math]::Min($chunkSize, $bytesRemaining)

            # Create an ArraySegment for the current chunk
            # Arguments: (byte[] array, int offset, int count)
            $bufferToSend = New-Object System.ArraySegment[byte]($fileBytes, $totalBytesSent, $currentChunkSize)

            # Determine if this is the final chunk
            $isLastChunk = ($totalBytesSent + $currentChunkSize -ge $fileBytes.Length)

            # Send the chunk asynchronously
            # Use Binary for raw file data, even if it's text. This ensures the server gets the bytes as is.
            # Set endOfMessage to $isLastChunk
            $sendTask = $webSocket.SendAsync($bufferToSend, [System.Net.WebSockets.WebSocketMessageType]::Binary, $isLastChunk, $cancellationToken)
            $sendTask.Wait() # Wait for the chunk to be sent

            $totalBytesSent += $currentChunkSize
            Write-Host "Sent $($currentChunkSize) bytes. Total sent: $($totalBytesSent)/$($fileBytes.Length)"
        }

        Write-Host "Payload sent successfully in chunks."

    } else {
        Write-Error "Failed to connect to WebSocket server. State: $($webSocket.State)"
    }
} catch {
    Write-Error "An error occurred during WebSocket connection or communication: $($_.Exception.Message)"
} finally {
    # Close the WebSocket connection
    if ($webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open -or `
        $webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Connecting) {
        Write-Host "Closing WebSocket connection."
        try {
            $webSocket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Closing", $cancellationToken).Wait()
        } catch {
            Write-Warning "Error closing WebSocket: $($_.Exception.Message)"
        }
    }
    $webSocket.Dispose()
    $cancellationTokenSource.Dispose()
    Write-Host "WebSocket client disposed."
    # The script will now exit.
}
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using WebApiSample.Data;
using WebApiSample.Models;
using WebApiSample.Services;

namespace WebApiSample.Controllers;

/// <summary>
/// Handles authentication
/// </summary>
[ApiController]
[Route("api/v1/[controller]")]
[Produces("application/json")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _context;
    private readonly ITokenService _tokenService;
    private readonly ILogger<AuthController> _logger;

    public AuthController(
        AppDbContext context,
        ITokenService tokenService,
        ILogger<AuthController> logger)
    {
        _context = context;
        _tokenService = tokenService;
        _logger = logger;
    }

    /// <summary>
    /// Authenticates a user and returns a JWT token
    /// </summary>
    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting("default")]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<AuthResponse>> Login(
        [FromBody] LoginRequest request,
        CancellationToken cancellationToken)
    {
        var user = await _context.Users
            .AsNoTracking()
            .FirstOrDefaultAsync(u => u.Email == request.Email, cancellationToken);

        if (user is null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
        {
            _logger.LogWarning(
                "Failed login attempt for {Email} from {IpAddress}",
                request.Email,
                HttpContext.Connection.RemoteIpAddress);

            return Unauthorized(new { message = "Invalid email or password" });
        }

        var token = _tokenService.GenerateAccessToken(user);
        var expiresAt = DateTime.UtcNow.AddMinutes(60);

        _logger.LogInformation("User {UserId} logged in successfully", user.Id);

        return Ok(new AuthResponse(token, expiresAt));
    }

    /// <summary>
    /// Registers a new user
    /// </summary>
    [HttpPost("register")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Register(
        [FromBody] RegisterRequest request,
        CancellationToken cancellationToken)
    {
        // Check if email or username exists
        var exists = await _context.Users
            .AnyAsync(u => u.Email == request.Email || u.Username == request.Username, cancellationToken);

        if (exists)
        {
            return Conflict(new { message = "Email or username already exists" });
        }

        var user = new User
        {
            Username = request.Username,
            Email = request.Email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            Role = "User",
            CreatedAt = DateTime.UtcNow
        };

        _context.Users.Add(user);
        await _context.SaveChangesAsync(cancellationToken);

        _logger.LogInformation("New user registered: {UserId}", user.Id);

        return CreatedAtAction(nameof(Login), new { message = "User registered successfully" });
    }

    /// <summary>
    /// Gets the current user's profile
    /// </summary>
    [HttpGet("me")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetCurrentUser(CancellationToken cancellationToken)
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;

        if (string.IsNullOrEmpty(userId))
            return Unauthorized();

        var user = await _context.Users
            .AsNoTracking()
            .Where(u => u.Id == int.Parse(userId))
            .Select(u => new
            {
                u.Id,
                u.Username,
                u.Email,
                u.Role,
                u.CreatedAt
            })
            .FirstOrDefaultAsync(cancellationToken);

        if (user is null)
            return Unauthorized();

        return Ok(user);
    }
}
